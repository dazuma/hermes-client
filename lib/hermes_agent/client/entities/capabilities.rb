# frozen_string_literal: true

require "hermes_agent/client/entity"

module HermesAgent
  class Client
    module Entities
      ##
      # The authentication scheme advertised by the server
      # ({Capabilities#auth}).
      #
      class Auth < Entity
        ##
        # The authentication type, e.g. `"bearer"`.
        # @return [String, nil]
        #
        def type
          self["type"]
        end

        ##
        # Whether authentication is required.
        # @return [boolean, nil]
        #
        def required?
          self["required"]
        end
      end

      ##
      # The server's execution model ({Capabilities#runtime}).
      #
      class Runtime < Entity
        ##
        # The runtime mode, e.g. `"server_agent"`.
        # @return [String, nil]
        #
        def mode
          self["mode"]
        end

        ##
        # Where tools execute, e.g. `"server"`.
        # @return [String, nil]
        #
        def tool_execution
          self["tool_execution"]
        end

        ##
        # Whether the runtime is split between client and server.
        # @return [boolean, nil]
        #
        def split_runtime?
          self["split_runtime"]
        end

        ##
        # A human-readable description of the runtime.
        # @return [String, nil]
        #
        def description
          self["description"]
        end
      end

      ##
      # The server's feature matrix ({Capabilities#features}).
      #
      # Each reader returns the advertised flag (a boolean), or `nil` when the
      # server does not advertise that feature. Readers are best-effort; use
      # {#[]} / {#to_h} for any feature not yet modeled here.
      #
      class Features < Entity
        ##
        # Whether the chat-completions endpoint is supported.
        # @return [boolean, nil]
        #
        def chat_completions?
          self["chat_completions"]
        end

        ##
        # Whether chat-completions streaming is supported.
        # @return [boolean, nil]
        #
        def chat_completions_streaming?
          self["chat_completions_streaming"]
        end

        ##
        # Whether the Responses API is supported.
        # @return [boolean, nil]
        #
        def responses_api?
          self["responses_api"]
        end

        ##
        # Whether Responses API streaming is supported.
        # @return [boolean, nil]
        #
        def responses_streaming?
          self["responses_streaming"]
        end

        ##
        # Whether run submission is supported.
        # @return [boolean, nil]
        #
        def run_submission?
          self["run_submission"]
        end

        ##
        # Whether run status polling is supported.
        # @return [boolean, nil]
        #
        def run_status?
          self["run_status"]
        end

        ##
        # Whether the run events SSE stream is supported.
        # @return [boolean, nil]
        #
        def run_events_sse?
          self["run_events_sse"]
        end

        ##
        # Whether stopping a run is supported.
        # @return [boolean, nil]
        #
        def run_stop?
          self["run_stop"]
        end

        ##
        # Whether responding to a run approval request is supported.
        # @return [boolean, nil]
        #
        def run_approval_response?
          self["run_approval_response"]
        end

        ##
        # Whether the server emits custom tool-progress events.
        # @return [boolean, nil]
        #
        def tool_progress_events?
          self["tool_progress_events"]
        end

        ##
        # Whether the server emits approval events.
        # @return [boolean, nil]
        #
        def approval_events?
          self["approval_events"]
        end

        ##
        # Whether CORS is enabled.
        # @return [boolean, nil]
        #
        def cors?
          self["cors"]
        end

        ##
        # The request header carrying the session-continuity id, e.g.
        # `"X-Hermes-Session-Id"`.
        # @return [String, nil]
        #
        def session_continuity_header
          self["session_continuity_header"]
        end

        ##
        # The request header carrying the session key, e.g.
        # `"X-Hermes-Session-Key"`.
        # @return [String, nil]
        #
        def session_key_header
          self["session_key_header"]
        end
      end

      ##
      # A single advertised route (one entry of {Capabilities#endpoints}).
      #
      class Endpoint < Entity
        ##
        # The HTTP method, e.g. `"GET"`. (Named `http_method` rather than
        # `method` to avoid shadowing `Object#method`.)
        # @return [String, nil]
        #
        def http_method
          self["method"]
        end

        ##
        # The request path, e.g. `"/v1/models"`. May contain `{...}`
        # placeholders such as `/v1/runs/{run_id}`.
        # @return [String, nil]
        #
        def path
          self["path"]
        end
      end

      ##
      # The server's advertised capabilities (`GET /v1/capabilities`).
      # Field readers are best-effort; {#to_h} remains the source of truth.
      #
      class Capabilities < Entity
        ##
        # The object type, `"hermes.api_server.capabilities"`.
        # @return [String, nil]
        #
        def object
          self["object"]
        end

        ##
        # The platform identifier, e.g. `"hermes-agent"`.
        # @return [String, nil]
        #
        def platform
          self["platform"]
        end

        ##
        # The configured server-side model id, e.g. `"hermes-test"`.
        # @return [String, nil]
        #
        def model
          self["model"]
        end

        ##
        # The authentication scheme, wrapped in an {Auth} entity. Returns
        # `nil` when the field is absent.
        # @return [Auth, nil]
        #
        def auth
          raw = self["auth"]
          raw.is_a?(::Hash) ? Auth.new(raw) : nil
        end

        ##
        # The execution model, wrapped in a {Runtime} entity. Returns `nil`
        # when the field is absent.
        # @return [Runtime, nil]
        #
        def runtime
          raw = self["runtime"]
          raw.is_a?(::Hash) ? Runtime.new(raw) : nil
        end

        ##
        # The feature matrix, wrapped in a {Features} entity. Returns `nil`
        # when the field is absent.
        # @return [Features, nil]
        #
        def features
          raw = self["features"]
          raw.is_a?(::Hash) ? Features.new(raw) : nil
        end

        ##
        # The advertised routes, keyed by logical name (e.g. `"models"`), each
        # value wrapped in an {Endpoint}. Returns `nil` when the field is
        # absent.
        # @return [Hash{String => Endpoint}, nil]
        #
        def endpoints
          raw = self["endpoints"]
          return nil unless raw.is_a?(::Hash)

          raw.transform_values { |value| Endpoint.new(value) }
        end
      end
    end
  end
end
