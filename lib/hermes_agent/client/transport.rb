# frozen_string_literal: true

require "json"

require "hermes_agent/client/util"

module HermesAgent
  class Client
    ##
    # The single chokepoint for HTTP communication with the server.
    #
    # Transport owns the underlying `http` gem connection, attaches the
    # `Authorization` header, serializes and parses JSON, and maps non-2xx
    # responses to the {Error} hierarchy. Resource objects build paths and
    # delegate here.
    #
    # Only the subset needed by the currently implemented resources is present;
    # more verbs (`patch`) and richer error mapping will be added as further
    # endpoints are built out.
    #
    class Transport
      ##
      # The outcome of a request whose response headers matter to the caller:
      # the parsed body — or, for a streaming request, the live chunk
      # enumerator — paired with the response headers as a Hash with downcased
      # string keys. Returned by {#post} and {#stream_post}; the header-agnostic
      # {#get} and {#delete} return the bare parsed body instead.
      #
      # @!attribute [r] body
      #   @return [Hash, Enumerator] The parsed JSON body, or the chunk
      #       enumerator for a streaming request.
      # @!attribute [r] headers
      #   @return [Hash{String=>String}] The response headers, keyed by
      #       downcased name.
      #
      Result = ::Data.define(:body, :headers)

      ##
      # Create a transport.
      #
      # @param config [Configuration] The connection settings to use.
      #
      def initialize(config)
        @config = config
      end

      ##
      # Issue a GET request and return the parsed JSON body.
      #
      # @param path [String] The request path, including any prefix such as
      #     `/v1` or `/health` (resources own their prefixes).
      # @return [Hash] The parsed response body, with string keys.
      # @raise [APIError] If the server returns a non-2xx response.
      #
      def get(path)
        response = request { client.get(url_for(path)) }
        handle(response)
      end

      ##
      # Issue a POST request with a JSON body and return the parsed JSON body.
      #
      # @param path [String] The request path, including any prefix such as
      #     `/v1` (resources own their prefixes).
      # @param body [Hash] The request body, serialized to JSON. The
      #     `Content-Type: application/json` header is set automatically.
      # @param headers [Hash, nil] Extra request headers to send, merged over
      #     the defaults (e.g. the session-continuity headers).
      # @return [Result] The parsed response body and the response headers.
      # @raise [APIError] If the server returns a non-2xx response.
      #
      def post(path, body, headers: nil)
        response = request { client(extra_headers: headers).post(url_for(path), json: body) }
        Result.new(body: handle(response), headers: normalize_headers(response.headers))
      end

      ##
      # Issue a PATCH request with a JSON body and return the parsed JSON body.
      #
      # Like {#get} and {#delete}, this returns the bare parsed body rather than
      # a {Result}: no PATCH endpoint surfaces response headers the caller needs.
      #
      # @param path [String] The request path, including any prefix such as
      #     `/v1` or `/api` (resources own their prefixes).
      # @param body [Hash] The request body, serialized to JSON. The
      #     `Content-Type: application/json` header is set automatically.
      # @return [Hash] The parsed response body, with string keys.
      # @raise [APIError] If the server returns a non-2xx response.
      #
      def patch(path, body)
        response = request { client.patch(url_for(path), json: body) }
        handle(response)
      end

      ##
      # Issue a DELETE request and return the parsed JSON body.
      #
      # @param path [String] The request path, including any prefix such as
      #     `/v1` (resources own their prefixes).
      # @return [Hash] The parsed response body, with string keys.
      # @raise [APIError] If the server returns a non-2xx response.
      #
      def delete(path)
        response = request { client.delete(url_for(path)) }
        handle(response)
      end

      ##
      # Open a streaming POST and return its live response body for an SSE
      # consumer ({Stream}). The response status is checked up front, so an
      # error response raises before any streaming begins; on success the body
      # is returned unread so it can be consumed incrementally.
      #
      # @param path [String] The request path, including its prefix.
      # @param body [Hash] The request body, serialized to JSON.
      # @param headers [Hash, nil] Extra request headers to send, merged over
      #     the defaults (e.g. the session-continuity headers).
      # @return [Result] The live chunk enumerator (as `body`) and the response
      #     headers. Iterate `body` with `#each` to read byte chunks as they
      #     arrive.
      # @raise [APIError] If the server returns a non-2xx response.
      #
      def stream_post(path, body, headers: nil)
        response = request { client(extra_headers: headers).post(url_for(path), json: body) }
        unless response.status.success?
          raise APIError.from_response(status: response.code, body: response.body.to_s,
                                       headers: response.headers.to_h)
        end
        Result.new(body: map_stream_errors(response.body), headers: normalize_headers(response.headers))
      end

      ##
      # Open a streaming GET and return its live response body for an SSE
      # consumer ({Stream}). Like {#stream_post}, the status is checked up front
      # so an error response raises before any streaming begins; on success the
      # body is returned unread for incremental consumption. The response
      # headers are not surfaced (this is the streaming counterpart of {#get},
      # which also returns the bare body).
      #
      # @param path [String] The request path, including its prefix.
      # @return [Enumerator] The live chunk enumerator. Iterate it with `#each`
      #     to read byte chunks as they arrive.
      # @raise [APIError] If the server returns a non-2xx response.
      #
      def stream_get(path)
        response = request { client.get(url_for(path)) }
        unless response.status.success?
          raise APIError.from_response(status: response.code, body: response.body.to_s,
                                       headers: response.headers.to_h)
        end
        map_stream_errors(response.body)
      end

      private

      ##
      # Wrap a streaming response body so transport-level failures hit while
      # reading it are mapped to the {Error} hierarchy.
      #
      # The body is read lazily, chunk by chunk, *after* {#stream_post} has
      # returned — so a socket or read-timeout failure mid-stream happens
      # outside {#request}'s rescue and would otherwise surface as the raw
      # `http`-gem exception. Iterating the returned enumerator re-reads the
      # body inside {#request}, so the same {TimeoutError}/{ConnectionError}
      # mapping applies. Chunks delivered before the failure are still yielded;
      # the exception is raised when the failing read is reached. Keeps {Stream}
      # HTTP-agnostic — it only ever sees mapped errors.
      #
      # @param body [#each] The live response body, yielding String chunks.
      # @return [Enumerator] The same chunks, with mid-stream failures mapped.
      #
      def map_stream_errors(body)
        ::Enumerator.new do |yielder|
          request { body.each { |chunk| yielder << chunk } }
        end
      end

      ##
      # Run an HTTP request, translating the `http` gem's transport-level
      # failures into the client's {Error} hierarchy.
      #
      # @yield The block that issues the request and returns its response.
      # @return [HTTP::Response]
      # @raise [TimeoutError] On an open or read timeout.
      # @raise [ConnectionError] On a socket, DNS, or TLS failure.
      #
      def request
        yield
      rescue ::HTTP::TimeoutError => e
        raise TimeoutError, e.message
      rescue ::HTTP::ConnectionError => e
        raise ConnectionError, e.message
      end

      ##
      # @param extra_headers [Hash, nil] Per-request headers merged over the
      #     defaults.
      # @return [HTTP::Client] A configured `http` client with auth and
      #     timeouts applied.
      #
      def client(extra_headers: nil)
        headers = extra_headers ? default_headers.merge(extra_headers) : default_headers
        result = ::HTTP.headers(headers)
        if @config.timeout || @config.open_timeout
          result = result.timeout(read: @config.timeout, connect: @config.open_timeout)
        end
        result
      end

      ##
      # Normalize response headers to a plain Hash keyed by downcased name,
      # keeping the layers above {Transport} free of the `http` gem's header
      # type. Repeated headers collapse to their first value.
      #
      # @param headers [#to_h] The response headers.
      # @return [Hash{String=>String}]
      #
      def normalize_headers(headers)
        headers.to_h.each_with_object({}) do |(name, value), result|
          result[name.to_s.downcase] = value.is_a?(::Array) ? value.first : value
        end
      end

      ##
      # @return [Hash] The headers sent on every request.
      #
      def default_headers
        headers = {"Accept" => "application/json"}
        headers["Authorization"] = "Bearer #{@config.api_key}" if @config.api_key
        headers
      end

      ##
      # @param path [String] A request path.
      # @return [String] The fully-qualified request URL.
      #
      def url_for(path)
        "#{@config.base_url.chomp('/')}#{path}"
      end

      ##
      # Parse a successful response or raise on a non-2xx status.
      #
      # @param response [HTTP::Response]
      # @return [Hash] The parsed JSON body.
      #
      def handle(response)
        body = response.body.to_s
        unless response.status.success?
          raise APIError.from_response(status: response.code, body: body,
                                       headers: response.headers.to_h)
        end
        body.empty? ? {} : Util.parse_json(body)
      end
    end
  end
end
