# frozen_string_literal: true

module HermesAgent
  class Client
    ##
    # A stateful, multi-turn conversation over the Responses API that chains its
    # turns automatically, so each call takes only the turn's `input:`.
    #
    # Construct one via {Resources::Responses#conversation} rather than directly:
    #
    #     convo = client.responses.conversation
    #     convo.create(input: "Hello").output_text
    #     convo.create(input: "And what about X?").output_text  # auto-chains
    #
    # There are two chaining mechanisms, selected at construction:
    #
    # - **id-tracking mode** (the default): the conversation remembers each
    #   turn's response id client-side and threads it into the next turn as
    #   `previous_response_id`. Pass `previous_response_id:` to resume such a
    #   thread from a known id (e.g. across process restarts).
    # - **named mode** (`name:`): every turn sends a stable `conversation` name
    #   and the server keeps the thread; no client-side id is threaded.
    #
    # The verb methods mirror {Resources::Responses} ({#create} /
    # {#stream_create}) and return the same entities and stream, so the helper
    # is a drop-in. {#last_response_id} is recorded in both modes for
    # inspection or persistence.
    #
    # A conversation models a single sequential thread and is not thread-safe:
    # issue and (for streaming) consume one turn before starting the next.
    #
    class Conversation
      ##
      # Create a conversation. Prefer {Resources::Responses#conversation}.
      #
      # @param responses [Resources::Responses] The responses resource to issue
      #     turns through.
      # @param name [String, nil] A conversation name for server-side chaining.
      #     Mutually exclusive with `previous_response_id`.
      # @param previous_response_id [String, nil] A prior response id to seed
      #     client-side chaining from. Mutually exclusive with `name`.
      # @raise [ArgumentError] If both `name` and `previous_response_id` are
      #     given (they select different chaining mechanisms).
      #
      # @private
      def initialize(responses, name: nil, previous_response_id: nil)
        raise ::ArgumentError, "name and previous_response_id are mutually exclusive" if name && previous_response_id

        @responses = responses
        @name = name
        @last_response_id = previous_response_id
      end

      ##
      # The conversation name, in named mode; `nil` in id-tracking mode.
      # @return [String, nil]
      #
      attr_reader :name

      ##
      # The id of the most recent turn's response (also the seed id before any
      # turn, in id-tracking mode). In named mode it is recorded for inspection
      # but not used for chaining.
      # @return [String, nil]
      #
      attr_reader :last_response_id

      ##
      # Create the next turn in the conversation.
      #
      # @param input [String, Array<Hash>] The turn's input (see
      #     {Resources::Responses#create}).
      # @param extra [Hash] Additional request-body fields merged into the body.
      # @return [Entities::Response] The response. Its id becomes
      #     {#last_response_id}.
      # @raise [APIError] If the server returns a non-2xx response.
      #
      def create(input:, **extra)
        response = @responses.create(input: input, **chaining, **extra)
        capture(response)
        response
      end

      ##
      # Create the next turn, streaming its events. Follows the same
      # block-or-enumerator contract as {Resources::Responses#stream_create}:
      # with a block, each event is yielded and the assembled
      # {Entities::Response} is returned; without one, a {Stream} is returned.
      # In either case the turn's response id is captured into
      # {#last_response_id} when the stream's result is built (during
      # consumption), so a subsequent turn chains onto it.
      #
      # @param input [String, Array<Hash>] The turn's input.
      # @param extra [Hash] Additional request-body fields merged into the body.
      # @yieldparam event [Entities::ResponseStreamEvent] Each streamed event.
      # @return [Entities::Response, Stream] The assembled response when a block
      #     is given, otherwise the {Stream}.
      # @raise [APIError] If the server returns a non-2xx response.
      #
      def stream_create(input:, **extra, &)
        @responses.stream_response(
          on_result: method(:capture), input: input, **chaining, **extra, &
        )
      end

      private

      ##
      # The chaining fields for the next turn: the conversation name in named
      # mode, the tracked previous response id in id-tracking mode, or none.
      #
      # @return [Hash]
      #
      def chaining
        return {conversation: @name} if @name
        return {previous_response_id: @last_response_id} if @last_response_id

        {}
      end

      ##
      # Record a turn's response id as {#last_response_id}, ignoring a missing
      # id (which would otherwise drop a previously tracked one).
      #
      # @param response [Entities::Response, nil] The turn's response.
      # @return [void]
      #
      def capture(response)
        id = response&.id
        @last_response_id = id if id
      end
    end
  end
end
