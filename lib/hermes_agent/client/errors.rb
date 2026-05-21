# frozen_string_literal: true

require "json"

module HermesAgent
  class Client
    ##
    # Base class for all errors raised by the client. Rescue this to catch
    # every failure mode the client can produce.
    #
    class Error < ::StandardError
    end

    ##
    # Raised when the client cannot reach the server at all: a socket, DNS, or
    # TLS failure that produced no HTTP response.
    #
    class ConnectionError < Error
    end

    ##
    # Raised when a request exceeds the configured open or read timeout.
    #
    class TimeoutError < Error
    end

    ##
    # Raised when the server returns a non-2xx HTTP response.
    #
    # The concrete class reflects the HTTP status: {BadRequestError},
    # {AuthenticationError}, {PermissionError}, {NotFoundError},
    # {RateLimitError}, or {ServerError}. A bare {APIError} is raised for any
    # status that maps to none of those.
    #
    # ## Error payloads
    #
    # The server uses two distinct error formats, both of which {from_response}
    # accommodates. Application-level errors (authentication, body validation,
    # missing resources) return an OpenAI-style JSON body of the form
    # `{"error": {"message", "type", "param"?, "code"?}}`, and {#error} exposes
    # that inner hash. Router-level errors (an unrouted path, a wrong method)
    # instead return a bare text body such as `"404: Not Found"`; for those
    # {#error} is `nil` and only {#body} is meaningful.
    #
    # Even within the JSON family the field set is inconsistent — `message` and
    # `type` are always present, but `param` and `code` may be null or absent —
    # so treat {#error} entries as best-effort. Do not switch on `type`/`code`
    # to classify a failure (the server returns `type: "invalid_request_error"`
    # even for `401`s); branch on the HTTP {#status} or the error subclass.
    #
    class APIError < Error
      ##
      # Build the {APIError} subclass that matches an HTTP error response,
      # extracting the structured payload when the server provides one.
      #
      # @param status [Integer] The HTTP status code.
      # @param body [String] The raw response body.
      # @param headers [Hash] The response headers.
      # @return [APIError] An instance of the subclass matching the status.
      #
      def self.from_response(status:, body:, headers: {})
        error = parse_error_payload(body)
        message = (error && error["message"]) || "Unexpected HTTP status #{status}"
        class_for_status(status).new(message, status: status, body: body,
                                              headers: headers, error: error)
      end

      # Pick the {APIError} subclass that represents an HTTP status code.
      def self.class_for_status(status)
        case status
        when 400, 422 then BadRequestError
        when 401 then AuthenticationError
        when 403 then PermissionError
        when 404 then NotFoundError
        when 429 then RateLimitError
        when 500..599 then ServerError
        else APIError
        end
      end
      private_class_method :class_for_status

      # Pull the inner `error` hash out of a response body, tolerating the
      # server's non-JSON (router-level) error bodies by returning nil.
      def self.parse_error_payload(body)
        parsed = ::JSON.parse(body.to_s)
        inner = parsed["error"] if parsed.is_a?(::Hash)
        inner if inner.is_a?(::Hash)
      rescue ::JSON::ParserError
        nil
      end
      private_class_method :parse_error_payload

      ##
      # Create an API error. Prefer {from_response}, which selects the correct
      # subclass and parses the payload for you.
      #
      # @param message [String] The human-readable error message.
      # @param status [Integer] The HTTP status code.
      # @param body [String] The raw response body.
      # @param headers [Hash] The response headers.
      # @param error [Hash, nil] The parsed structured error hash, if the body
      #     carried one.
      #
      def initialize(message, status:, body:, headers: {}, error: nil)
        super(message)
        @status = status
        @body = body
        @headers = headers
        @error = error
      end

      ##
      # The HTTP status code of the error response.
      # @return [Integer]
      #
      attr_reader :status

      ##
      # The raw response body.
      # @return [String]
      #
      attr_reader :body

      ##
      # The response headers.
      # @return [Hash]
      #
      attr_reader :headers

      ##
      # The structured error payload (the inner `error` object), or `nil` when
      # the server returned a non-JSON body. Field set is best-effort: expect
      # `message` and `type`, but `param` and `code` may be missing.
      # @return [Hash, nil]
      #
      attr_reader :error
    end

    ##
    # Raised on a `400` or `422` response: the request was malformed or failed
    # server-side validation.
    #
    class BadRequestError < APIError
    end

    ##
    # Raised on a `401` response: the bearer token was missing or invalid.
    #
    class AuthenticationError < APIError
    end

    ##
    # Raised on a `403` response: the token is valid but not permitted to
    # perform the request.
    #
    class PermissionError < APIError
    end

    ##
    # Raised on a `404` response: the requested resource does not exist.
    #
    class NotFoundError < APIError
    end

    ##
    # Raised on a `429` response: the client has been rate limited.
    #
    class RateLimitError < APIError
    end

    ##
    # Raised on a `5xx` response: the server failed to handle the request.
    #
    class ServerError < APIError
    end
  end
end
