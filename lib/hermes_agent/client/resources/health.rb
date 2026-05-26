# frozen_string_literal: true

require "hermes_agent/client/entities/health"

module HermesAgent
  class Client
    ##
    # Resource groups, each exposing the verb methods for one area of the API.
    # Reached through accessors on {Client}, such as {Client#health}.
    #
    module Resources
      ##
      # The health resource. Health endpoints live at the server root, not
      # under the `/v1` prefix.
      #
      class Health
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
        # Check whether the server is healthy.
        #
        # @return [Entities::Health] The health result; {Entities::Health#status}
        #     is `"ok"` on a healthy server.
        #
        def check
          Entities::Health.new(@transport.get("/health"))
        end

        ##
        # Fetch detailed server health, including gateway state, per-platform
        # connection status, and the active-agent count.
        #
        # @return [Entities::HealthDetails] The detailed health result.
        #
        def detailed
          Entities::HealthDetails.new(@transport.get("/health/detailed"))
        end
      end
    end
  end
end
