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
      # The result of a chat completion (`POST /v1/chat/completions`).
      # Field readers are best-effort; {#to_h} remains the source of truth.
      #
      class ChatCompletion < Entity
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
