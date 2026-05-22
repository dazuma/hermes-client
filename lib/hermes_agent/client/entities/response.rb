# frozen_string_literal: true

require "hermes_agent/client/entity"

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
      # {#call_id} and {#output}). Readers for fields that do not apply to the
      # item's type return `nil`.
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
        # The result of a `function_call_output` item, as the raw JSON string
        # the server emitted (not parsed).
        # @return [String, nil]
        #
        def output
          self["output"]
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
