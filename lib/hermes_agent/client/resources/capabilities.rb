# frozen_string_literal: true

require "hermes_agent/client/entities/capabilities"

module HermesAgent
  class Client
    module Resources
      ##
      # The capabilities resource: the server's self-description of the
      # endpoints and features it supports (`/v1/capabilities`).
      #
      class Capabilities
        ##
        # Create the resource.
        #
        # @param transport [Transport] The transport used to issue requests.
        #
        # @private
        def initialize(transport)
          @transport = transport
        end

        ##
        # Fetch the server's advertised capabilities.
        #
        # @return [Entities::Capabilities] The capabilities document.
        #
        def get
          Entities::Capabilities.new(@transport.get("/v1/capabilities"))
        end
      end
    end
  end
end
