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

      ##
      # The connection status of a single platform within a detailed health
      # check (one entry of {HealthDetails#platforms}).
      #
      class PlatformStatus < Entity
        ##
        # The connection state, e.g. `"connected"`.
        # @return [String, nil]
        #
        def state
          self["state"]
        end

        ##
        # A machine-readable error code, or `nil` when there is no error.
        # @return [String, nil]
        #
        def error_code
          self["error_code"]
        end

        ##
        # A human-readable error message, or `nil` when there is no error.
        # @return [String, nil]
        #
        def error_message
          self["error_message"]
        end

        ##
        # When this platform status was last updated (ISO-8601 timestamp
        # string).
        # @return [String, nil]
        #
        def updated_at
          self["updated_at"]
        end
      end

      ##
      # The result of a detailed server health check (`/health/detailed`).
      # Field readers are best-effort; {#to_h} remains the source of truth.
      #
      class HealthDetails < Entity
        ##
        # The reported health status, e.g. `"ok"`.
        # @return [String, nil]
        #
        def status
          self["status"]
        end

        ##
        # The platform identifier, e.g. `"hermes-agent"`.
        # @return [String, nil]
        #
        def platform
          self["platform"]
        end

        ##
        # The gateway's lifecycle state, e.g. `"running"`.
        # @return [String, nil]
        #
        def gateway_state
          self["gateway_state"]
        end

        ##
        # The per-platform connection state, keyed by platform name (e.g.
        # `"api_server"`), each value wrapped in a {PlatformStatus}. Returns
        # `nil` when the field is absent.
        # @return [Hash{String => PlatformStatus}, nil]
        #
        def platforms
          raw = self["platforms"]
          return nil unless raw.is_a?(::Hash)

          raw.transform_values { |value| PlatformStatus.new(value) }
        end

        ##
        # The number of agents currently running on the server.
        # @return [Integer, nil]
        #
        def active_agents
          self["active_agents"]
        end

        ##
        # The reason the gateway exited, or `nil` while it is running.
        # @return [String, nil]
        #
        def exit_reason
          self["exit_reason"]
        end

        ##
        # When this health snapshot was produced (ISO-8601 timestamp string).
        # @return [String, nil]
        #
        def updated_at
          self["updated_at"]
        end

        ##
        # The process id of the running gateway.
        # @return [Integer, nil]
        #
        def pid
          self["pid"]
        end
      end
    end
  end
end
