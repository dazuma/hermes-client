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
      # a `cancelled` or `failed` run — so both readers tolerate a missing
      # value. A `failed` run instead carries an {#error} message. Field readers
      # are best-effort; {#to_h} remains the source of truth.
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
        # The failure message on a `failed` run (the upstream error, e.g. a
        # model/provider error). Present only when {#status} is `"failed"`;
        # `nil` otherwise. A failed run otherwise looks like a cancelled one —
        # {#output} and {#usage} are absent.
        # @return [String, nil]
        #
        def error
          self["error"]
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

      ##
      # One event in a streamed run ({Resources::Runs#stream_events}).
      #
      # Unlike chat and the Responses API, the run events stream uses plain
      # `data:` frames — there is no SSE `event:` line and no `[DONE]` sentinel
      # — so each event carries its type in an `"event"` payload field (read via
      # {#event}) alongside {#run_id} and a {#timestamp}. The stream has no
      # head frame; it begins at the first content event. Which other readers
      # are meaningful depends on {#event}; the rest return `nil`. Observed
      # types: `tool.started`/`tool.completed`, `message.delta`,
      # `reasoning.available`, the terminal `run.completed`/`run.cancelled`/
      # `run.failed` (the last carries an {#error} string), and
      # `approval.request`/`approval.responded`.
      #
      class RunEvent < Entity
        ##
        # The terminal lifecycle event of a streamed run: the last event whose
        # {#event} type is a `run.*` frame (`run.completed`, `run.cancelled`, or
        # `run.failed`). Returns `nil` if the stream closed without one (e.g. it
        # was cut short). Used as the aggregated {Stream#result} of
        # {Resources::Runs#stream_events}.
        #
        # @param events [Array<RunEvent>] The streamed events, in order.
        # @return [RunEvent, nil]
        #
        def self.terminal(events)
          events.reverse_each.find { |event| event.event&.start_with?("run.") }
        end

        ##
        # The event type, e.g. `"message.delta"` or `"run.completed"`.
        # @return [String, nil]
        #
        def event
          self["event"]
        end

        ##
        # The id of the run this event belongs to (`"run_…"`).
        # @return [String, nil]
        #
        def run_id
          self["run_id"]
        end

        ##
        # When the event was emitted, as a Unix timestamp (seconds, fractional).
        # @return [Float, nil]
        #
        def timestamp
          self["timestamp"]
        end

        ##
        # The tool name on a `tool.started` / `tool.completed` event, e.g.
        # `"terminal"`.
        # @return [String, nil]
        #
        def tool
          self["tool"]
        end

        ##
        # A preview of the tool invocation on a `tool.started` event (e.g. the
        # command to be run).
        # @return [String, nil]
        #
        def preview
          self["preview"]
        end

        ##
        # The tool's execution time on a `tool.completed` event, in seconds.
        # @return [Float, nil]
        #
        def duration
          self["duration"]
        end

        ##
        # Whether the tool reported an error on a `tool.completed` event. This
        # is the tool *result* signal, not a lifecycle marker: a failed command
        # — or a denied approval — reports `true` yet the run can still complete.
        # Returns `nil` when there is no boolean flag (the field is absent, or
        # the event is a `run.failed` whose `error` is a message string — read
        # that via {#error}).
        # @return [boolean, nil]
        #
        def error?
          value = self["error"]
          value if [true, false].include?(value)
        end

        ##
        # The failure message on a `run.failed` event (a string — the upstream
        # error). `nil` on any other event, including a `tool.completed` whose
        # `error` is the boolean result flag (read that via {#error?}). The two
        # readers split the overloaded `error` payload field by type.
        # @return [String, nil]
        #
        def error
          value = self["error"]
          value if value.is_a?(::String)
        end

        ##
        # The incremental assistant text on a `message.delta` event.
        # @return [String, nil]
        #
        def delta
          self["delta"]
        end

        ##
        # The full reasoning text on a `reasoning.available` event.
        # @return [String, nil]
        #
        def text
          self["text"]
        end

        ##
        # The assembled final assistant text on a `run.completed` event.
        # @return [String, nil]
        #
        def output
          self["output"]
        end

        ##
        # The token usage on a `run.completed` event, wrapped in a {RunUsage}.
        # Returns `nil` when the field is absent.
        # @return [RunUsage, nil]
        #
        def usage
          raw = self["usage"]
          raw.is_a?(::Hash) ? RunUsage.new(raw) : nil
        end

        ##
        # The command awaiting approval on an `approval.request` event.
        # @return [String, nil]
        #
        def command
          self["command"]
        end

        ##
        # The matched approval pattern key on an `approval.request` event.
        # @return [String, nil]
        #
        def pattern_key
          self["pattern_key"]
        end

        ##
        # All matched approval pattern keys on an `approval.request` event.
        # Returns `nil` when the field is absent.
        # @return [Array<String>, nil]
        #
        def pattern_keys
          self["pattern_keys"]
        end

        ##
        # A human-readable description of the gated command on an
        # `approval.request` event.
        # @return [String, nil]
        #
        def description
          self["description"]
        end

        ##
        # The valid approval choices on an `approval.request` event (e.g.
        # `["once", "session", "always", "deny"]`). Returns `nil` when the field
        # is absent.
        # @return [Array<String>, nil]
        #
        def choices
          self["choices"]
        end

        ##
        # The choice that resolved an approval on an `approval.responded` event.
        # @return [String, nil]
        #
        def choice
          self["choice"]
        end

        ##
        # The count of approvals resolved on an `approval.responded` event.
        # @return [Integer, nil]
        #
        def resolved
          self["resolved"]
        end
      end

      ##
      # The acknowledgement returned by responding to a run's pending approval
      # ({Resources::Runs#respond_approval}): `{object:
      # "hermes.run.approval_response", run_id, choice, resolved}`. The run then
      # resumes (the gated tool executes on an approve, or is aborted on a
      # deny — though a denied run still ends `completed`); observe the
      # `approval.responded` and `tool.completed` frames on the event stream, or
      # poll {Resources::Runs#get}, for the outcome.
      #
      class RunApprovalResponse < Entity
        ##
        # The object type, `"hermes.run.approval_response"`.
        # @return [String, nil]
        #
        def object
          self["object"]
        end

        ##
        # The id of the run whose approval was answered (`"run_…"`).
        # @return [String, nil]
        #
        def run_id
          self["run_id"]
        end

        ##
        # The choice that was submitted: `"once"`, `"session"`, `"always"`, or
        # `"deny"`.
        # @return [String, nil]
        #
        def choice
          self["choice"]
        end

        ##
        # The number of pending approvals resolved by the response.
        # @return [Integer, nil]
        #
        def resolved
          self["resolved"]
        end
      end
    end
  end
end
