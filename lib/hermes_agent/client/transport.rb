# frozen_string_literal: true

require "json"

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
    # more verbs (`patch`, `delete`) and richer error mapping will be added as
    # further endpoints are built out.
    #
    class Transport
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
      # @return [Hash] The parsed response body, with string keys.
      # @raise [APIError] If the server returns a non-2xx response.
      #
      def post(path, body)
        response = request { client.post(url_for(path), json: body) }
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
      # @return [HTTP::Response::Body] The live response body; iterate it with
      #     `#each` to read byte chunks as they arrive.
      # @raise [APIError] If the server returns a non-2xx response.
      #
      def stream_post(path, body)
        response = request { client.post(url_for(path), json: body) }
        unless response.status.success?
          raise APIError.from_response(status: response.code, body: response.body.to_s,
                                       headers: response.headers.to_h)
        end
        response.body
      end

      private

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
      # @return [HTTP::Client] A configured `http` client with auth and
      #     timeouts applied.
      #
      def client
        result = ::HTTP.headers(default_headers)
        if @config.timeout || @config.open_timeout
          result = result.timeout(read: @config.timeout, connect: @config.open_timeout)
        end
        result
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
        body.empty? ? {} : ::JSON.parse(body)
      end
    end
  end
end
