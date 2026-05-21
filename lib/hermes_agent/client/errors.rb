# frozen_string_literal: true

module HermesAgent
  class Client
    ##
    # Base class for all errors raised by the client. Rescue this to catch
    # every failure mode the client can produce.
    #
    class Error < ::StandardError
    end

    ##
    # Raised when the server returns a non-2xx HTTP response.
    #
    # The full error hierarchy described in the design (status-specific
    # subclasses) will be filled in as more of the API is implemented; for now
    # this carries the raw status and body.
    #
    class APIError < Error
      ##
      # Create an API error.
      #
      # @param message [String] The human-readable error message.
      # @param status [Integer] The HTTP status code.
      # @param body [String] The raw response body.
      #
      def initialize(message, status:, body:)
        super(message)
        @status = status
        @body = body
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
    end
  end
end
