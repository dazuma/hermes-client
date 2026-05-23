# frozen_string_literal: true

require "hermes_agent/client/entity"
require "hermes_agent/client/entities/session_headers"

module HermesAgent
  class Client
    module Entities
      ##
      # The token usage reported for a {Response} ({Response#usage}). Note the
      # Responses API uses different field names than chat completions:
      # `input_tokens`/`output_tokens` rather than
      # `prompt_tokens`/`completion_tokens`.
      #
      class ResponseUsage < Entity
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
      # One content part within a message {ResponseOutputItem} (an entry of
      # {ResponseOutputItem#content}), e.g. `{type: "output_text", text: "…"}`.
      #
      class ResponseContent < Entity
        ##
        # The content-part type, e.g. `"output_text"`.
        # @return [String, nil]
        #
        def type
          self["type"]
        end

        ##
        # The text of the part (for an `output_text` part).
        # @return [String, nil]
        #
        def text
          self["text"]
        end
      end

      ##
      # One item in a {Response}'s `output` array. The output is heterogeneous:
      # an item's `type` selects which readers are meaningful. Observed types
      # are `"message"` (an assistant reply, with {#role} and {#content}),
      # `"function_call"` (a tool invocation, with {#name}, {#arguments}, and
      # {#call_id}), and `"function_call_output"` (a tool result, with
      # {#call_id}, {#output}, and {#output_text}). Readers for fields that do
      # not apply to the item's type return `nil`. {#id} and {#status} are
      # populated only on items carried by streaming `response.output_item.*`
      # events, not on items read off a final {Response}.
      #
      class ResponseOutputItem < Entity
        ##
        # The item type: `"message"`, `"function_call"`, or
        # `"function_call_output"`.
        # @return [String, nil]
        #
        def type
          self["type"]
        end

        ##
        # The item id (`"msg_…"`, `"fc_…"`, or `"fco_…"`). Present on items
        # carried by streaming `response.output_item.*` events; `nil` for items
        # read off a final {Response}'s `output` (the server omits it there).
        # @return [String, nil]
        #
        def id
          self["id"]
        end

        ##
        # The item lifecycle status, e.g. `"in_progress"` or `"completed"`.
        # Present on items carried by streaming `response.output_item.*` events;
        # `nil` for items read off a final {Response}'s `output`. Like all such
        # statuses it is a lifecycle marker, not a success signal.
        # @return [String, nil]
        #
        def status
          self["status"]
        end

        ##
        # The author role of a `message` item, e.g. `"assistant"`.
        # @return [String, nil]
        #
        def role
          self["role"]
        end

        ##
        # The content parts of a `message` item, each wrapped in a
        # {ResponseContent}. Returns `nil` when the field is absent.
        # @return [Array<ResponseContent>, nil]
        #
        def content
          raw = self["content"]
          return nil unless raw.is_a?(::Array)

          raw.map { |part| ResponseContent.new(part) }
        end

        ##
        # The tool name of a `function_call` item.
        # @return [String, nil]
        #
        def name
          self["name"]
        end

        ##
        # The arguments of a `function_call` item, as the raw JSON string the
        # server emitted (not parsed).
        # @return [String, nil]
        #
        def arguments
          self["arguments"]
        end

        ##
        # The tool-call id linking a `function_call` to its
        # `function_call_output`.
        # @return [String, nil]
        #
        def call_id
          self["call_id"]
        end

        ##
        # The raw result of a `function_call_output` item, as the server
        # emitted it. The shape differs by representation: a **raw JSON string**
        # in non-streaming (POST/GET) bodies, but an **array of content parts**
        # (`[{ "type" => "input_text", "text" => … }]`) in the streaming
        # representation. Use {#output_text} for the result text regardless of
        # shape.
        # @return [String, Array<Hash>, nil]
        #
        def output
          self["output"]
        end

        ##
        # The result text of a `function_call_output` item, normalized across
        # both {#output} shapes: the string itself when non-streaming, or the
        # concatenated `text` of the content parts when streaming. Returns `nil`
        # when there is no `output` (e.g. a non-output item).
        # @return [String, nil]
        #
        def output_text
          raw = self["output"]
          return raw if raw.is_a?(::String)
          return nil unless raw.is_a?(::Array)

          raw.filter_map { |part| part["text"] if part.is_a?(::Hash) }.join
        end

        ##
        # The assembled text of a `message` item: the concatenation of its
        # `output_text` content parts. Returns `nil` for an item with no
        # content (e.g. a tool item).
        # @return [String, nil]
        #
        def text
          parts = content
          return nil unless parts

          parts.filter_map { |part| part.text if part.type == "output_text" }.join
        end
      end

      ##
      # A response from the Responses API (`POST /v1/responses`,
      # `GET /v1/responses/{id}`). The server persists conversation state, so a
      # response can be retrieved later and chained from. Field readers are
      # best-effort; {#to_h} remains the source of truth.
      #
      class Response < Entity
        include SessionHeaders

        ##
        # Build a {Response} from a streamed turn's events. The terminal
        # `response.completed` event carries the full final response object, so
        # this takes the last `response` payload seen across the events (which
        # is that terminal one — `response.created` carries an interim one).
        # Returns a {Response} wrapping an empty payload if no event carried a
        # `response` object.
        #
        # @param events [Array<ResponseStreamEvent>] The streamed events, in
        #     order.
        # @param session_id [String, nil] The session id from the response
        #     headers, carried onto the assembled response.
        # @param session_key [String, nil] The session key from the response
        #     headers, carried onto the assembled response.
        # @return [Response]
        #
        def self.from_events(events, session_id: nil, session_key: nil)
          payload = {}
          events.each do |event|
            raw = event["response"]
            payload = raw if raw.is_a?(::Hash)
          end
          new(payload, session_id: session_id, session_key: session_key)
        end

        ##
        # The response id, e.g. `"resp_…"`. Pass it as `previous_response_id` to
        # chain a follow-up turn.
        # @return [String, nil]
        #
        def id
          self["id"]
        end

        ##
        # The object type, `"response"`.
        # @return [String, nil]
        #
        def object
          self["object"]
        end

        ##
        # The response status, e.g. `"completed"` or `"in_progress"`.
        # @return [String, nil]
        #
        def status
          self["status"]
        end

        ##
        # When the response was created, as a Unix timestamp (seconds).
        # @return [Integer, nil]
        #
        def created_at
          self["created_at"]
        end

        ##
        # The model that produced the response, e.g. `"hermes-test"`.
        # @return [String, nil]
        #
        def model
          self["model"]
        end

        ##
        # The output items, each wrapped in a {ResponseOutputItem}. Returns
        # `nil` when the field is absent.
        # @return [Array<ResponseOutputItem>, nil]
        #
        def output
          raw = self["output"]
          return nil unless raw.is_a?(::Array)

          raw.map { |item| ResponseOutputItem.new(item) }
        end

        ##
        # The token usage, wrapped in a {ResponseUsage}. Returns `nil` when the
        # field is absent.
        # @return [ResponseUsage, nil]
        #
        def usage
          raw = self["usage"]
          raw.is_a?(::Hash) ? ResponseUsage.new(raw) : nil
        end

        ##
        # The assistant's text: the concatenation of the text of every
        # `message` output item, ignoring tool items. A convenience over
        # {#output} for the common single-message case. Returns `nil` when
        # there is no output.
        # @return [String, nil]
        #
        def output_text
          items = output
          return nil unless items

          items.select { |item| item.type == "message" }.filter_map(&:text).join
        end
      end

      ##
      # One event in a streamed Responses turn ({Resources::Responses#stream_create}).
      #
      # The Responses API emits **named** SSE events; each payload repeats the
      # name in its {#type} and carries a 0-based {#sequence_number}. The
      # observed sequence for a simple turn is `response.created` →
      # `response.output_item.added` → `response.output_text.delta` (one per
      # delta) → `response.output_text.done` → `response.output_item.done` →
      # `response.completed` (terminal; there is no `[DONE]` sentinel). Which
      # readers are meaningful depends on {#type}; the rest return `nil`.
      #
      class ResponseStreamEvent < Entity
        ##
        # The event type, e.g. `"response.output_text.delta"` or
        # `"response.completed"`.
        # @return [String, nil]
        #
        def type
          self["type"]
        end

        ##
        # The 0-based sequence number of this event within the turn.
        # @return [Integer, nil]
        #
        def sequence_number
          self["sequence_number"]
        end

        ##
        # The incremental text on a `response.output_text.delta` event.
        # @return [String, nil]
        #
        def delta
          self["delta"]
        end

        ##
        # The assembled text on a `response.output_text.done` event.
        # @return [String, nil]
        #
        def text
          self["text"]
        end

        ##
        # The id of the output item a text delta/done event applies to
        # (`"msg_…"`).
        # @return [String, nil]
        #
        def item_id
          self["item_id"]
        end

        ##
        # The index of the output item this event applies to.
        # @return [Integer, nil]
        #
        def output_index
          self["output_index"]
        end

        ##
        # The index of the content part within the item this event applies to.
        # @return [Integer, nil]
        #
        def content_index
          self["content_index"]
        end

        ##
        # The nested response object on a `response.created` or
        # `response.completed` event, wrapped in a {Response}. Returns `nil` on
        # events that carry no response object.
        # @return [Response, nil]
        #
        def response
          raw = self["response"]
          raw.is_a?(::Hash) ? Response.new(raw) : nil
        end

        ##
        # The nested output item on a `response.output_item.added` or
        # `response.output_item.done` event, wrapped in a
        # {ResponseOutputItem}. Returns `nil` on events that carry no item.
        # @return [ResponseOutputItem, nil]
        #
        def item
          raw = self["item"]
          raw.is_a?(::Hash) ? ResponseOutputItem.new(raw) : nil
        end
      end

      ##
      # The result of deleting a response (`DELETE /v1/responses/{id}`):
      # `{id, object: "response", deleted: true}`.
      #
      class ResponseDeletion < Entity
        ##
        # The id of the deleted response.
        # @return [String, nil]
        #
        def id
          self["id"]
        end

        ##
        # The object type, `"response"`.
        # @return [String, nil]
        #
        def object
          self["object"]
        end

        ##
        # Whether the response was deleted.
        # @return [boolean, nil]
        #
        def deleted?
          self["deleted"]
        end
      end
    end
  end
end
