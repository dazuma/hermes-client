# frozen_string_literal: true

module HermesAgent
  class Client
    ##
    # Connection settings for a {HermesAgent::Client}.
    #
    # Holds the server location and credentials shared by all requests. An
    # instance is created when a client is constructed and may be customized
    # either via keyword arguments or by yielding the configuration to a block.
    #
    class Configuration
      ##
      # The default server root URL.
      # @return [String]
      #
      DEFAULT_BASE_URL = "http://127.0.0.1:8642"

      ##
      # The default keep-alive timeout, in seconds.
      # @return [Numeric]
      #
      DEFAULT_KEEP_ALIVE_TIMEOUT = 5

      ##
      # Create a configuration.
      #
      # @param base_url [String] The server root URL, _without_ a path prefix
      #     such as `/v1`. Defaults to {DEFAULT_BASE_URL}.
      # @param api_key [String, nil] The bearer token sent on every request, or
      #     `nil` to send no `Authorization` header. Defaults to the
      #     `HERMES_API_KEY` environment variable.
      # @param read_timeout [Numeric, nil] The read timeout in seconds, or `nil`
      #     for no client-side limit.
      # @param open_timeout [Numeric, nil] The connection-open timeout in
      #     seconds, or `nil` for no client-side limit.
      # @param write_timeout [Numeric, nil] The timeout in seconds for writing
      #     a request, or `nil` for no client-side limit.
      # @param keep_alive_timeout [Numeric] How long, in seconds, an idle
      #     persistent connection may be reused before it is considered stale
      #     and reopened on the next request. Defaults to
      #     {DEFAULT_KEEP_ALIVE_TIMEOUT}.
      #
      def initialize(base_url: DEFAULT_BASE_URL,
                     api_key: ::ENV.fetch("HERMES_API_KEY", nil),
                     read_timeout: nil,
                     open_timeout: nil,
                     write_timeout: nil,
                     keep_alive_timeout: DEFAULT_KEEP_ALIVE_TIMEOUT)
        @base_url = base_url
        @api_key = api_key
        @read_timeout = read_timeout
        @open_timeout = open_timeout
        @write_timeout = write_timeout
        @keep_alive_timeout = keep_alive_timeout
      end

      ##
      # The server root URL, without a path prefix.
      # @return [String]
      #
      attr_accessor :base_url

      ##
      # The bearer token sent on every request, or `nil` for none.
      # @return [String, nil]
      #
      attr_accessor :api_key

      ##
      # The read timeout in seconds, or `nil` for no client-side limit.
      # @return [Numeric, nil]
      #
      attr_accessor :read_timeout

      ##
      # The connection-open timeout in seconds, or `nil` for no client-side
      # limit.
      # @return [Numeric, nil]
      #
      attr_accessor :open_timeout

      ##
      # The request-write timeout in seconds, or `nil` for no client-side
      # limit.
      # @return [Numeric, nil]
      #
      attr_accessor :write_timeout

      ##
      # How long, in seconds, an idle persistent connection may be reused before
      # it is considered stale and reopened on the next request.
      # @return [Numeric]
      #
      attr_accessor :keep_alive_timeout
    end
  end
end
