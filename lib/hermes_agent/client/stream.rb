# frozen_string_literal: true

require "json"

require "hermes_agent/client/errors"
require "hermes_agent/client/util"

module HermesAgent
  class Client
    ##
    # A consumable Server-Sent Events stream.
    #
    # `Stream` parses the SSE frames emitted by a streaming endpoint, wrapping
    # each frame's `data` payload (parsed as JSON) in an event wrapper object,
    # and implements the block-or-enumerator contract:
    #
    # - Iterated with a block (via {#each}), it yields each event as it
    #   arrives, giving natural backpressure over the network read.
    # - Without a block it is an `Enumerable` the caller drives itself.
    #
    # After the stream is fully consumed, {#result} returns the aggregated
    # final object (built by the aggregator block given at construction). It is
    # a **single-pass** stream over a live network read: it can be iterated
    # once.
    #
    # The class is HTTP-agnostic — it consumes anything that yields String
    # byte chunks via `#each` (the `http` gem's response body, or an array of
    # chunks in tests) — which keeps {Transport} the sole owner of the
    # connection.
    #
    class Stream
      include ::Enumerable

      ##
      # Create a stream.
      #
      # @param chunks [#each] A source of String byte chunks (e.g. an `http`
      #     response body).
      # @param event_class [Class] The {Entity} subclass each frame's parsed
      #     data is wrapped in.
      # @param terminator [String, nil] A sentinel `data` payload that marks
      #     the end of the stream (e.g. `"[DONE]"` for chat completions). The
      #     terminator frame is not yielded. `nil` means the stream simply
      #     ends when the connection closes.
      # @yieldparam events [Array<Entity>] All events seen, in order; the
      #     block returns the aggregated {#result}. Optional — without it
      #     {#result} is `nil`.
      #
      def initialize(chunks, event_class:, terminator: nil, &aggregator)
        @chunks = chunks
        @event_class = event_class
        @terminator = terminator
        @aggregator = aggregator
        @buffer = +""
        @data_lines = []
        @events = []
        @consumed = false
        @result = nil
      end

      ##
      # Iterate the events. With a block, yields each event as it is parsed and
      # returns `self`. Without a block, returns an `Enumerator`.
      #
      # @yieldparam event [Entity] Each parsed event, in order.
      # @return [self, Enumerator]
      # @raise [Error] If the stream has already been consumed.
      #
      def each(&block)
        return enum_for(:each) unless block

        raise Error, "Stream has already been consumed" if @consumed

        consume(&block)
        self
      end

      ##
      # The aggregated final object, available after the stream is consumed.
      # Consuming the stream first if it has not been iterated.
      #
      # @return [Object, nil] Whatever the aggregator block returned, or `nil`
      #     when no aggregator was given.
      #
      def result
        consume unless @consumed
        @result
      end

      private

      ##
      # Read every chunk, parse frames, accumulate events, and build the
      # aggregated result. Yields each event if a block is given.
      #
      def consume
        @consumed = true
        @chunks.each do |chunk|
          @buffer << chunk
          while (newline = @buffer.index("\n"))
            event = process_line(@buffer.slice!(0, newline + 1).chomp)
            next unless event

            @events << event
            yield event if block_given?
          end
        end
        @result = @aggregator&.call(@events)
      end

      ##
      # Process one SSE line. Accumulates `data` fields and, on a blank line,
      # dispatches the buffered frame.
      #
      # @param line [String] One line, without its trailing newline.
      # @return [Entity, nil] The event when a frame completes, else `nil`.
      #
      def process_line(line)
        return dispatch if line.empty?
        return nil if line.start_with?(":")

        field, separator, value = line.partition(":")
        value = value.sub(/\A /, "") unless separator.empty?
        @data_lines << value if field == "data"
        nil
      end

      ##
      # Emit the buffered frame, unless it is empty or the terminator.
      #
      # @return [Entity, nil]
      #
      def dispatch
        return nil if @data_lines.empty?

        data = @data_lines.join("\n")
        @data_lines = []
        return nil if @terminator && data == @terminator

        @event_class.new(Util.parse_json(data))
      end
    end
  end
end
