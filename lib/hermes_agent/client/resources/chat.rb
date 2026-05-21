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
      end
    end
  end
end
