# frozen_string_literal: true

require "hermes_agent/client/entities/model"

module HermesAgent
  class Client
    module Resources
      ##
      # The models resource: discovery of the models the server advertises
      # (`/v1/models`).
      #
      class Models
        ##
        # Create the resource.
        #
        # @param transport [Transport] The transport used to issue requests.
        #
        def initialize(transport)
          @transport = transport
        end

        ##
        # List the models the server advertises.
        #
        # @return [Array<Entities::Model>] The advertised models. Empty when
        #     the server returns no `data` array.
        #
        def list
          data = @transport.get("/v1/models")["data"]
          return [] unless data.is_a?(::Array)

          data.map { |item| Entities::Model.new(item) }
        end
      end
    end
  end
end
