# frozen_string_literal: true

require "hermes_agent/client/entities/response"
require "hermes_agent/client/conversation"
require "hermes_agent/client/util"

module HermesAgent
  class Client
    module Resources
      ##
      # The responses resource: the Responses API (`/v1/responses`). Unlike
      # chat completions, the server persists conversation state, so turns can
      # be chained (via `previous_response_id` or a named `conversation`) and a
      # response can be retrieved or deleted by id afterward. On a server
      # configured with an API key, these calls require a bearer token (see
      # {Client} / {Configuration}).
      #
      # Server-side storage is capped (LRU eviction), so callers should not
      # assume an older response remains retrievable.
      #
      class Responses
        ##
        # Create the resource.
        #
        # @param transport [Transport] The transport used to issue requests.
        #
        def initialize(transport)
          @transport = transport
        end

        ##
        # Create a response.
        #
        # No `model` is sent: the model is configured server-side and the
        # server ignores a client-supplied one. (A caller who really wants to
        # send fields we have not modeled — including `model` — can pass them
        # through `extra`.)
        #
        # @param input [String, Array<Hash>] The input: a plain string, or an
        #     array of input items (which may include `input_image` parts for
        #     inline images).
        # @param previous_response_id [String, nil] The id of a prior response
        #     to chain this turn onto. Omitted from the request when `nil`.
        # @param conversation [String, nil] A stable conversation name to chain
        #     this turn onto. Omitted from the request when `nil`.
        # @param idempotency_key [String, nil] An idempotency key, sent as the
        #     `Idempotency-Key` request header. The server caches the result for
        #     ~5 minutes and replays it for a repeat call carrying the same key
        #     and an equivalent request, so a retry does not re-run the model.
        #     The replay is **transparent**: the response is indistinguishable
        #     from a fresh one (same status, no replay header, and a freshly
        #     regenerated `id`), so there is no way — here or in the returned
        #     entity — to tell whether a given call was served from the cache.
        #     Reusing a key with a *different* request silently recomputes (no
        #     error) and overwrites the cached entry. Honored only on this
        #     non-streaming endpoint (not on {#stream_create}).
        # @param extra [Hash] Additional request-body fields merged into the
        #     body as-is.
        # @return [Entities::Response] The response. Its
        #     {Entities::SessionHeaders#session_id} carries the server-generated
        #     session id from the response headers (this endpoint does not
        #     accept a session on the request).
        # @raise [APIError] If the server returns a non-2xx response.
        #
        def create(input:, previous_response_id: nil, conversation: nil, idempotency_key: nil, **extra)
          body = build_body(input, previous_response_id, conversation, extra)
          headers = idempotency_key ? {"Idempotency-Key" => idempotency_key} : nil
          result = @transport.post("/v1/responses", body, headers: headers)
          Entities::Response.new(result.body, **Util.session_headers(result.headers))
        end

        ##
        # Create a response, streaming the turn's events.
        #
        # With a block, each {Entities::ResponseStreamEvent} is yielded as it
        # arrives and the assembled {Entities::Response} is returned once the
        # stream closes. Without a block, a {Stream} is returned for the caller
        # to iterate; its {Stream#result} is the assembled response. The final
        # response is taken from the terminal `response.completed` event (see
        # {Entities::Response.from_events}).
        #
        # @param input [String, Array<Hash>] The input (see {#create}).
        # @param previous_response_id [String, nil] The id of a prior response
        #     to chain onto. Omitted from the request when `nil`.
        # @param conversation [String, nil] A stable conversation name to chain
        #     onto. Omitted from the request when `nil`.
        # @param extra [Hash] Additional request-body fields merged into the
        #     body as-is.
        # @yieldparam event [Entities::ResponseStreamEvent] Each streamed event.
        # @return [Entities::Response, Stream] The assembled response when a
        #     block is given, otherwise the {Stream}.
        # @raise [APIError] If the server returns a non-2xx response.
        #
        def stream_create(input:, previous_response_id: nil, conversation: nil, **extra, &)
          stream_response(on_result: nil, input: input, previous_response_id: previous_response_id,
                          conversation: conversation, **extra, &)
        end

        ##
        # Create a streamed response, with an optional hook invoked with the
        # assembled {Entities::Response} once the stream is consumed. This is
        # the shared implementation behind {#stream_create}; the `on_result`
        # hook is folded into the stream's aggregator (so it fires exactly when
        # the final response is built, for both the block and enumerator forms)
        # rather than exposed as a settable hook on the returned {Stream}, where
        # a caller could clobber it. It exists for {Conversation} to capture the
        # new response id for chaining; it is not part of the public API.
        #
        # @!visibility private
        # @param on_result [#call, nil] Called with the assembled
        #     {Entities::Response} when the stream's result is built. May be nil.
        # @param input [String, Array<Hash>] The input (see {#create}).
        # @param previous_response_id [String, nil] The prior response id to
        #     chain onto. Omitted from the request when nil.
        # @param conversation [String, nil] A conversation name to chain onto.
        #     Omitted from the request when nil.
        # @param extra [Hash] Additional request-body fields.
        # @yieldparam event [Entities::ResponseStreamEvent] Each streamed event.
        # @return [Entities::Response, Stream] The assembled response when a
        #     block is given, otherwise the {Stream}.
        #
        def stream_response(on_result:, input:, previous_response_id: nil, conversation: nil, **extra, &block)
          body = build_body(input, previous_response_id, conversation, extra)
          body[:stream] = true
          result = @transport.stream_post("/v1/responses", body)
          session = Util.session_headers(result.headers)
          stream = Stream.new(result.body, event_class: Entities::ResponseStreamEvent) do |events|
            response = Entities::Response.from_events(events, **session)
            on_result&.call(response)
            response
          end
          return stream unless block

          stream.each(&block)
          stream.result
        end

        ##
        # Begin a multi-turn conversation that automatically chains its turns.
        #
        # Returns a {Conversation} — a stateful helper wrapping this resource —
        # whose `create` / `stream_create` take only the per-turn `input:` (plus
        # `extra`) and handle chaining for you. With no arguments it tracks the
        # `previous_response_id` of each turn client-side and threads it into the
        # next; pass `name:` instead to chain via a server-side named
        # conversation; pass `previous_response_id:` to resume a client-side
        # thread from a known id. `name:` and `previous_response_id:` are
        # mutually exclusive (they select different chaining mechanisms).
        #
        # @param name [String, nil] A stable conversation name for server-side
        #     chaining. Mutually exclusive with `previous_response_id`.
        # @param previous_response_id [String, nil] A prior response id to seed
        #     client-side chaining from. Mutually exclusive with `name`.
        # @return [Conversation]
        #
        def conversation(name: nil, previous_response_id: nil)
          Conversation.new(self, name: name, previous_response_id: previous_response_id)
        end

        ##
        # Retrieve a previously created response by id.
        #
        # @param id [String] The response id (`"resp_…"`).
        # @return [Entities::Response] The response.
        # @raise [NotFoundError] If no such response exists (or it was evicted).
        # @raise [APIError] If the server returns another non-2xx response.
        #
        def get(id)
          Entities::Response.new(@transport.get("/v1/responses/#{id}"))
        end

        ##
        # Delete a response by id.
        #
        # @param id [String] The response id (`"resp_…"`).
        # @return [Entities::ResponseDeletion] The deletion result.
        # @raise [APIError] If the server returns a non-2xx response.
        #
        def delete(id)
          Entities::ResponseDeletion.new(@transport.delete("/v1/responses/#{id}"))
        end

        private

        ##
        # Build the request body, including chaining fields only when present.
        #
        # @param input [String, Array<Hash>] The input.
        # @param previous_response_id [String, nil] The prior response id.
        # @param conversation [String, nil] The conversation name.
        # @param extra [Hash] Additional body fields.
        # @return [Hash] The request body.
        #
        def build_body(input, previous_response_id, conversation, extra)
          body = {input: input, **extra}
          body[:previous_response_id] = previous_response_id if previous_response_id
          body[:conversation] = conversation if conversation
          body
        end
      end
    end
  end
end
