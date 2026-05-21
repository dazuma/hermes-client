# frozen_string_literal: true

require "hermes_agent/client/entities/chat_completion"

module HermesAgent
  class Client
    module Resources
      ##
      # The chat resource: OpenAI-compatible chat completions
      # (`POST /v1/chat/completions`). This endpoint is stateless — each call
      # is independent — and, on a server configured with an API key, requires
      # a bearer token (see {Client} / {Configuration}).
      #
      class Chat
        ##
        # Create the resource.
        #
        # @param transport [Transport] The transport used to issue requests.
        #
        def initialize(transport)
          @transport = transport
        end

        ##
        # Create a chat completion.
        #
        # No `model` is sent: the model is configured server-side and the
        # server ignores a client-supplied one. (A caller who really wants to
        # send fields we have not modeled — including `model` — can pass them
        # through `extra`.)
        #
        # @param messages [Array<Hash>] The OpenAI-style message array. Each
        #     message is a hash such as `{role: "user", content: "…"}`;
        #     content may include `image_url` parts for inline images.
        # @param extra [Hash] Additional request-body fields (e.g. sampling
        #     parameters) merged into the body as-is.
        # @return [Entities::ChatCompletion] The completion.
        # @raise [APIError] If the server returns a non-2xx response.
        #
        def create(messages:, **extra)
          body = {messages: messages, **extra}
          Entities::ChatCompletion.new(@transport.post("/v1/chat/completions", body))
        end

        ##
        # Create a chat completion, streaming the response.
        #
        # With a block, each {Entities::ChatCompletionChunk} is yielded as it
        # arrives and the assembled {Entities::ChatCompletion} is returned once
        # the stream closes. Without a block, a {Stream} is returned for the
        # caller to iterate; its {Stream#result} is the assembled completion.
        #
        # @param messages [Array<Hash>] The OpenAI-style message array (see
        #     {#create}).
        # @param extra [Hash] Additional request-body fields merged into the
        #     body as-is.
        # @yieldparam chunk [Entities::ChatCompletionChunk] Each streamed chunk.
        # @return [Entities::ChatCompletion, Stream] The assembled completion
        #     when a block is given, otherwise the {Stream}.
        # @raise [APIError] If the server returns a non-2xx response.
        #
        def stream_create(messages:, **extra, &block)
          body = {messages: messages, stream: true, **extra}
          chunks = @transport.stream_post("/v1/chat/completions", body)
          stream = Stream.new(chunks, event_class: Entities::ChatCompletionChunk, terminator: "[DONE]") do |events|
            Entities::ChatCompletion.from_chunks(events)
          end
          return stream unless block

          stream.each(&block)
          stream.result
        end
      end
    end
  end
end
