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
        # The SSE `event:` name of the server's custom tool-progress frames,
        # which are routed to {Entities::ChatToolProgress} rather than treated
        # as completion chunks.
        #
        TOOL_PROGRESS_EVENT = "hermes.tool.progress"

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
        # While the server agent executes tools it interleaves custom
        # `hermes.tool.progress` frames; these are surfaced as
        # {Entities::ChatToolProgress} events (distinct from the text
        # {Entities::ChatCompletionChunk}s) and are not folded into the
        # assembled completion.
        #
        # With a block, each event is yielded as it arrives and the assembled
        # {Entities::ChatCompletion} is returned once the stream closes. Without
        # a block, a {Stream} is returned for the caller to iterate; its
        # {Stream#result} is the assembled completion.
        #
        # @param messages [Array<Hash>] The OpenAI-style message array (see
        #     {#create}).
        # @param extra [Hash] Additional request-body fields merged into the
        #     body as-is.
        # @yieldparam event [Entities::ChatCompletionChunk, Entities::ChatToolProgress]
        #     Each streamed event: a text chunk, or a tool-progress frame.
        # @return [Entities::ChatCompletion, Stream] The assembled completion
        #     when a block is given, otherwise the {Stream}.
        # @raise [APIError] If the server returns a non-2xx response.
        #
        def stream_create(messages:, **extra, &block)
          body = {messages: messages, stream: true, **extra}
          chunks = @transport.stream_post("/v1/chat/completions", body)
          event_class = lambda do |name|
            name == TOOL_PROGRESS_EVENT ? Entities::ChatToolProgress : Entities::ChatCompletionChunk
          end
          stream = Stream.new(chunks, event_class: event_class, terminator: "[DONE]") do |events|
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
