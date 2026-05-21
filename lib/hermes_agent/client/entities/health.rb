# frozen_string_literal: true

require "hermes_agent/client/entity"

module HermesAgent
  class Client
    ##
    # Wrapper objects for the payloads the server returns. Each is a subclass
    # of {Entity}.
    #
    module Entities
      ##
      # The result of a server health check.
      #
      class Health < Entity
        ##
        # The reported health status, e.g. `"ok"`.
        # @return [String, nil]
        #
        def status
          self["status"]
        end
      end
    end
  end
end
