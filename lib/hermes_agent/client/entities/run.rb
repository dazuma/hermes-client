# frozen_string_literal: true

require "hermes_agent/client/entity"

module HermesAgent
  class Client
    module Entities
      ##
      # The token usage reported for a {Run} ({Run#usage}). Like the Responses
      # API (and unlike chat completions), runs report
      # `input_tokens`/`output_tokens` rather than
      # `prompt_tokens`/`completion_tokens`.
      #
      class RunUsage < Entity
        ##
        # The number of tokens in the input.
        # @return [Integer, nil]
        #
        def input_tokens
          self["input_tokens"]
        end

        ##
        # The number of tokens in the generated output.
        # @return [Integer, nil]
        #
        def output_tokens
          self["output_tokens"]
        end

        ##
        # The total number of tokens used (input plus output).
        # @return [Integer, nil]
        #
        def total_tokens
          self["total_tokens"]
        end
      end

      ##
      # A run from the Runs API (`POST /v1/runs`, `GET /v1/runs/{id}`). Unlike
      # chat/responses a run is server-side asynchronous: `create` returns
      # immediately with a minimal run (only {#run_id} and {#status}), and
      # progress is tracked by polling ({Resources::Runs#get}) or subscribing to
      # the event stream. {#output} and {#usage} are populated only once the run
      # reaches a terminal `completed` status, and are absent before then and on
      # a `cancelled` run — so both readers tolerate a missing value. Field
      # readers are best-effort; {#to_h} remains the source of truth.
      #
      class Run < Entity
        ##
        # The run id, e.g. `"run_…"` (`run_` plus 32 hex characters). Pass it to
        # {Resources::Runs#get} to poll, or to the streaming/stop/approval calls.
        # @return [String, nil]
        #
        def run_id
          self["run_id"]
        end
        alias id run_id

        ##
        # The object type, `"hermes.run"`.
        # @return [String, nil]
        #
        def object
          self["object"]
        end

        ##
        # The run status: `"started"` → `"running"` → terminal `"completed"` /
        # `"cancelled"` / `"failed"`, with `"waiting_for_approval"` while a gated
        # tool awaits a response and a transient `"stopping"` after a stop.
        # @return [String, nil]
        #
        def status
          self["status"]
        end

        ##
        # When the run was created, as a Unix timestamp (seconds, fractional).
        # @return [Float, nil]
        #
        def created_at
          self["created_at"]
        end

        ##
        # When the run was last updated, as a Unix timestamp (seconds,
        # fractional).
        # @return [Float, nil]
        #
        def updated_at
          self["updated_at"]
        end

        ##
        # The session correlation label for the run (defaults to the {#run_id}
        # when none was supplied on create).
        # @return [String, nil]
        #
        def session_id
          self["session_id"]
        end

        ##
        # The model that produced the run, e.g. `"hermes-test"` (configured
        # server-side).
        # @return [String, nil]
        #
        def model
          self["model"]
        end

        ##
        # The name of the most recent event emitted on the run's event stream,
        # e.g. `"run.completed"`. Empty at the very start of a run.
        # @return [String, nil]
        #
        def last_event
          self["last_event"]
        end

        ##
        # The assembled final assistant text, present once the run completes.
        # Absent (nil) before the run is terminal and on a cancelled run.
        # @return [String, nil]
        #
        def output
          self["output"]
        end

        ##
        # The token usage, wrapped in a {RunUsage}. Present once the run
        # completes; returns `nil` when the field is absent (before terminal, or
        # on a cancelled run).
        # @return [RunUsage, nil]
        #
        def usage
          raw = self["usage"]
          raw.is_a?(::Hash) ? RunUsage.new(raw) : nil
        end
      end

      ##
      # The acknowledgement returned by stopping a run
      # ({Resources::Runs#stop}): `{run_id, status: "stopping"}`. Stop is
      # cooperative — this ack only confirms the stop was accepted; the run
      # then resolves to a terminal `"cancelled"` status, observable by polling
      # {Resources::Runs#get}. It is deliberately not a full {Run} (it carries
      # no output, usage, or timestamps).
      #
      class RunStop < Entity
        ##
        # The id of the run being stopped (`"run_…"`).
        # @return [String, nil]
        #
        def run_id
          self["run_id"]
        end

        ##
        # The status acknowledged by the stop, `"stopping"`.
        # @return [String, nil]
        #
        def status
          self["status"]
        end
      end
    end
  end
end
