# frozen_string_literal: true

require "hermes_agent/client/entities/chat_completion"
require "hermes_agent/client/util"

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
        # @param session_id [String, nil] A session id to continue, sent as the
        #     `X-Hermes-Session-ID` request header. When omitted, the server
        #     generates a fresh one (returned on {Entities::SessionHeaders#session_id}).
        # @param session_key [String, nil] A session key, sent as the
        #     `X-Hermes-Session-Key` request header.
        # @param extra [Hash] Additional request-body fields (e.g. sampling
        #     parameters) merged into the body as-is.
        # @return [Entities::ChatCompletion] The completion, carrying the
        #     session headers returned by the server.
        # @raise [APIError] If the server returns a non-2xx response.
        #
        def create(messages:, session_id: nil, session_key: nil, **extra)
          body = {messages: messages, **extra}
          result = @transport.post("/v1/chat/completions", body,
                                   headers: session_request_headers(session_id, session_key))
          Entities::ChatCompletion.new(result.body, **Util.session_headers(result.headers))
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
        # @param session_id [String, nil] A session id to continue, sent as the
        #     `X-Hermes-Session-ID` request header (see {#create}).
        # @param session_key [String, nil] A session key, sent as the
        #     `X-Hermes-Session-Key` request header (see {#create}).
        # @param extra [Hash] Additional request-body fields merged into the
        #     body as-is.
        # @yieldparam event [Entities::ChatCompletionChunk, Entities::ChatToolProgress]
        #     Each streamed event: a text chunk, or a tool-progress frame.
        # @return [Entities::ChatCompletion, Stream] The assembled completion
        #     (carrying the server's session headers) when a block is given,
        #     otherwise the {Stream}.
        # @raise [APIError] If the server returns a non-2xx response.
        #
        def stream_create(messages:, session_id: nil, session_key: nil, **extra, &block)
          body = {messages: messages, stream: true, **extra}
          result = @transport.stream_post("/v1/chat/completions", body,
                                          headers: session_request_headers(session_id, session_key))
          session = Util.session_headers(result.headers)
          event_class = lambda do |name|
            name == TOOL_PROGRESS_EVENT ? Entities::ChatToolProgress : Entities::ChatCompletionChunk
          end
          stream = Stream.new(result.body, event_class: event_class, terminator: "[DONE]") do |events|
            Entities::ChatCompletion.from_chunks(events, **session)
          end
          return stream unless block

          stream.each(&block)
          stream.result
        end

        private

        ##
        # Build the session-continuity request headers, omitting either header
        # the caller did not supply. Returns an empty hash when neither is set.
        #
        # @param session_id [String, nil] The session id, if any.
        # @param session_key [String, nil] The session key, if any.
        # @return [Hash{String=>String}]
        #
        def session_request_headers(session_id, session_key)
          headers = {}
          headers["X-Hermes-Session-ID"] = session_id if session_id
          headers["X-Hermes-Session-Key"] = session_key if session_key
          headers
        end
      end
    end
  end
end
