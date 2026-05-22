# frozen_string_literal: true

require "hermes_agent/client/entity"

module HermesAgent
  class Client
    module Entities
      ##
      # A single message in a chat completion (the `message` of a
      # {ChatChoice}).
      #
      class ChatMessage < Entity
        ##
        # The role of the message author, e.g. `"assistant"`.
        # @return [String, nil]
        #
        def role
          self["role"]
        end

        ##
        # The message content. For a plain text completion this is the
        # assistant's reply string; it may be `nil` (e.g. for tool calls).
        # @return [String, nil]
        #
        def content
          self["content"]
        end
      end

      ##
      # The token usage reported for a chat completion ({ChatCompletion#usage}).
      #
      class ChatUsage < Entity
        ##
        # The number of tokens in the prompt.
        # @return [Integer, nil]
        #
        def prompt_tokens
          self["prompt_tokens"]
        end

        ##
        # The number of tokens in the generated completion.
        # @return [Integer, nil]
        #
        def completion_tokens
          self["completion_tokens"]
        end

        ##
        # The total number of tokens used (prompt plus completion).
        # @return [Integer, nil]
        #
        def total_tokens
          self["total_tokens"]
        end
      end

      ##
      # One choice in a chat completion (one entry of
      # {ChatCompletion#choices}).
      #
      class ChatChoice < Entity
        ##
        # The position of this choice in the list.
        # @return [Integer, nil]
        #
        def index
          self["index"]
        end

        ##
        # Why generation stopped, e.g. `"stop"`.
        # @return [String, nil]
        #
        def finish_reason
          self["finish_reason"]
        end

        ##
        # The generated message, wrapped in a {ChatMessage}. Returns `nil`
        # when the field is absent.
        # @return [ChatMessage, nil]
        #
        def message
          raw = self["message"]
          raw.is_a?(::Hash) ? ChatMessage.new(raw) : nil
        end
      end

      ##
      # One streamed chunk of a chat completion (`object:
      # "chat.completion.chunk"`), as emitted by
      # {Resources::Chat#stream_create}. The convenience readers reflect the
      # first choice (`choices[0]`), which is the common single-choice case;
      # use {#to_h} / {#[]} for multi-choice streams.
      #
      class ChatCompletionChunk < Entity
        ##
        # The completion id (carried on every chunk for a turn).
        # @return [String, nil]
        #
        def id
          self["id"]
        end

        ##
        # The object type, `"chat.completion.chunk"`.
        # @return [String, nil]
        #
        def object
          self["object"]
        end

        ##
        # When the completion was created, as a Unix timestamp (seconds).
        # @return [Integer, nil]
        #
        def created
          self["created"]
        end

        ##
        # The model producing the completion.
        # @return [String, nil]
        #
        def model
          self["model"]
        end

        ##
        # The incremental text carried by this chunk — the first choice's
        # `delta.content`. `nil` on chunks that carry no text (e.g. the opening
        # role chunk and the final chunk).
        # @return [String, nil]
        #
        def delta
          first_delta["content"]
        end

        ##
        # The author role, present on the opening chunk — the first choice's
        # `delta.role`.
        # @return [String, nil]
        #
        def role
          first_delta["role"]
        end

        ##
        # Why generation stopped, present on the final chunk — the first
        # choice's `finish_reason`.
        # @return [String, nil]
        #
        def finish_reason
          first_choice["finish_reason"]
        end

        ##
        # The token usage, present on the final chunk, wrapped in a
        # {ChatUsage}. Returns `nil` when absent.
        # @return [ChatUsage, nil]
        #
        def usage
          raw = self["usage"]
          raw.is_a?(::Hash) ? ChatUsage.new(raw) : nil
        end

        private

        ##
        # @return [Hash] The first choice, or an empty hash.
        #
        def first_choice
          choices = self["choices"]
          (choices.is_a?(::Array) ? choices.first : nil) || {}
        end

        ##
        # @return [Hash] The first choice's delta, or an empty hash.
        #
        def first_delta
          delta = first_choice["delta"]
          delta.is_a?(::Hash) ? delta : {}
        end
      end

      ##
      # A custom `hermes.tool.progress` event emitted on the chat-completions
      # stream while the server agent executes a tool. It is a distinct event
      # type from {ChatCompletionChunk} — it carries no `choices`/`delta` and is
      # never folded into the assembled {ChatCompletion} — so tool activity does
      # not pollute the assistant text. The Responses API does not emit these
      # (it represents tool activity as `function_call` output items instead).
      #
      # Each tool call produces two events keyed by {#tool_call_id}: a
      # `"running"` event carrying {#emoji} and {#label}, then a `"completed"`
      # event that omits them. `status` is a lifecycle marker only — a tool that
      # fails (or times out) still reports `"completed"`; the failure surfaces in
      # the tool's result, not here.
      #
      class ChatToolProgress < Entity
        ##
        # The tool name, e.g. `"search_files"` or `"terminal"`.
        # @return [String, nil]
        #
        def tool
          self["tool"]
        end

        ##
        # A decorative emoji for the tool, present on the `"running"` event.
        # @return [String, nil]
        #
        def emoji
          self["emoji"]
        end

        ##
        # A short human-facing descriptor of the invocation (e.g. the search
        # glob `"*"`, or the command `"ls -F"`), present on the `"running"`
        # event.
        # @return [String, nil]
        #
        def label
          self["label"]
        end

        ##
        # The id correlating this event's `"running"` and `"completed"` frames
        # (read from the camelCase `toolCallId` wire field), e.g. `"call_…"`.
        # @return [String, nil]
        #
        def tool_call_id
          self["toolCallId"]
        end

        ##
        # The lifecycle status, `"running"` or `"completed"`.
        # @return [String, nil]
        #
        def status
          self["status"]
        end

        ##
        # Whether this event marks the tool starting to run.
        # @return [boolean]
        #
        def running?
          status == "running"
        end

        ##
        # Whether this event marks the tool finishing execution. Note this is a
        # lifecycle marker, not a success signal — see the class docs.
        # @return [boolean]
        #
        def completed?
          status == "completed"
        end
      end

      ##
      # The result of a chat completion (`POST /v1/chat/completions`).
      # Field readers are best-effort; {#to_h} remains the source of truth.
      #
      class ChatCompletion < Entity
        ##
        # Reconstruct a completion from the events of a streamed turn. Chat
        # streaming does not send a final aggregate object, so this assembles
        # one: the message text is the concatenation of every chunk's
        # `delta.content`, the role and finish_reason are taken from the chunks
        # that carry them, and the usage from the final chunk. Single-choice
        # (`choices[0]`) is assumed. Non-chunk events (e.g. {ChatToolProgress})
        # are ignored, so the assembled text holds only the assistant's reply.
        #
        # @param events [Array<Entity>] The streamed events, in order; only
        #     {ChatCompletionChunk}s contribute to the result.
        # @return [ChatCompletion]
        #
        def self.from_chunks(events)
          chunks = events.select { |event| event.is_a?(ChatCompletionChunk) }
          first = chunks.empty? ? {} : chunks.first.to_h
          content = +""
          role = nil
          finish_reason = nil
          usage = nil
          chunks.each do |chunk|
            role ||= chunk.role
            content << chunk.delta if chunk.delta
            finish_reason = chunk.finish_reason if chunk.finish_reason
            usage = chunk["usage"] if chunk["usage"]
          end
          new(
            "id" => first["id"], "object" => "chat.completion",
            "created" => first["created"], "model" => first["model"],
            "choices" => [{"index" => 0,
                           "message" => {"role" => role, "content" => content},
                           "finish_reason" => finish_reason}],
            "usage" => usage
          )
        end

        ##
        # The completion id, e.g. `"chatcmpl-…"`.
        # @return [String, nil]
        #
        def id
          self["id"]
        end

        ##
        # The object type, `"chat.completion"`.
        # @return [String, nil]
        #
        def object
          self["object"]
        end

        ##
        # When the completion was created, as a Unix timestamp (seconds).
        # @return [Integer, nil]
        #
        def created
          self["created"]
        end

        ##
        # The model that produced the completion, e.g. `"hermes-test"`.
        # @return [String, nil]
        #
        def model
          self["model"]
        end

        ##
        # The generated choices, each wrapped in a {ChatChoice}. Returns `nil`
        # when the field is absent.
        # @return [Array<ChatChoice>, nil]
        #
        def choices
          raw = self["choices"]
          return nil unless raw.is_a?(::Array)

          raw.map { |item| ChatChoice.new(item) }
        end

        ##
        # The token usage, wrapped in a {ChatUsage}. Returns `nil` when the
        # field is absent.
        # @return [ChatUsage, nil]
        #
        def usage
          raw = self["usage"]
          raw.is_a?(::Hash) ? ChatUsage.new(raw) : nil
        end
      end
    end
  end
end
