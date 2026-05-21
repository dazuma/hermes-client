# frozen_string_literal: true

require "http/cookie"
require "http"

require "hermes_agent/client/version"
require "hermes_agent/client/configuration"
require "hermes_agent/client/errors"
require "hermes_agent/client/transport"
require "hermes_agent/client/resources/capabilities"
require "hermes_agent/client/resources/health"
require "hermes_agent/client/resources/models"

##
# Classes related to the Hermes agent
#
module HermesAgent
  ##
  # A client for the Hermes API server.
  #
  # Construct a client with the server location and credentials, then reach
  # endpoints through resource accessors such as {#health}.
  #
  #     client = HermesAgent::Client.new(base_url: "http://127.0.0.1:8642")
  #     client.health.check.status  # => "ok"
  #
  class Client
    ##
    # Create a client.
    #
    # Settings may be supplied as keyword arguments, by yielding the
    # {Configuration} to a block, or both (the block runs after the keyword
    # arguments are applied).
    #
    # @param base_url [String] The server root URL. See {Configuration}.
    # @param api_key [String, nil] The bearer token. See {Configuration}.
    # @param timeout [Numeric, nil] The read timeout in seconds.
    # @param open_timeout [Numeric, nil] The connection-open timeout in seconds.
    # @yieldparam config [Configuration] The configuration, for customization.
    #
    def initialize(base_url: Configuration::DEFAULT_BASE_URL,
                   api_key: ENV.fetch("HERMES_API_KEY", nil),
                   timeout: nil,
                   open_timeout: nil)
      @config = Configuration.new(base_url: base_url, api_key: api_key,
                                  timeout: timeout, open_timeout: open_timeout)
      yield @config if block_given?
      @transport = Transport.new(@config)
    end

    ##
    # The configuration this client was built with.
    # @return [Configuration]
    #
    attr_reader :config

    ##
    # The capabilities resource (the server's advertised endpoints and
    # feature matrix).
    # @return [Resources::Capabilities]
    #
    def capabilities
      @capabilities ||= Resources::Capabilities.new(@transport)
    end

    ##
    # The health resource (server health checks).
    # @return [Resources::Health]
    #
    def health
      @health ||= Resources::Health.new(@transport)
    end

    ##
    # The models resource (discovery of advertised models).
    # @return [Resources::Models]
    #
    def models
      @models ||= Resources::Models.new(@transport)
    end
  end
end
