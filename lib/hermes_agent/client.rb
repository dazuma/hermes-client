# frozen_string_literal: true

require "hermes_agent/client/version"
require "hermes_agent/client/configuration"
require "hermes_agent/client/errors"
require "hermes_agent/client/util"
require "hermes_agent/client/stream"
require "hermes_agent/client/transport"
require "hermes_agent/client/conversation"
require "hermes_agent/client/resources/capabilities"
require "hermes_agent/client/resources/chat"
require "hermes_agent/client/resources/health"
require "hermes_agent/client/resources/jobs"
require "hermes_agent/client/resources/models"
require "hermes_agent/client/resources/responses"
require "hermes_agent/client/resources/runs"

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
  # Note this class is not thread-safe. When using in a multithreaded
  # application, you should create a separate client object per thread.
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
    # @param keep_alive_timeout [Numeric] How long an idle persistent
    #     connection may be reused before being reopened. See {Configuration}.
    # @yieldparam config [Configuration] The configuration, for customization.
    #
    def initialize(base_url: Configuration::DEFAULT_BASE_URL,
                   api_key: ENV.fetch("HERMES_API_KEY", nil),
                   timeout: nil,
                   open_timeout: nil,
                   keep_alive_timeout: Configuration::DEFAULT_KEEP_ALIVE_TIMEOUT)
      @config = Configuration.new(base_url: base_url, api_key: api_key,
                                  timeout: timeout, open_timeout: open_timeout,
                                  keep_alive_timeout: keep_alive_timeout)
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
    # The chat resource (OpenAI-compatible chat completions).
    # @return [Resources::Chat]
    #
    def chat
      @chat ||= Resources::Chat.new(@transport)
    end

    ##
    # The health resource (server health checks).
    # @return [Resources::Health]
    #
    def health
      @health ||= Resources::Health.new(@transport)
    end

    ##
    # The jobs resource (the Jobs API, for scheduled background work).
    # @return [Resources::Jobs]
    #
    def jobs
      @jobs ||= Resources::Jobs.new(@transport)
    end

    ##
    # The models resource (discovery of advertised models).
    # @return [Resources::Models]
    #
    def models
      @models ||= Resources::Models.new(@transport)
    end

    ##
    # The responses resource (the Responses API, with server-side
    # conversation state).
    # @return [Resources::Responses]
    #
    def responses
      @responses ||= Resources::Responses.new(@transport)
    end

    ##
    # The runs resource (the Runs API, for long-running server-side agent
    # runs).
    # @return [Resources::Runs]
    #
    def runs
      @runs ||= Resources::Runs.new(@transport)
    end
  end
end
