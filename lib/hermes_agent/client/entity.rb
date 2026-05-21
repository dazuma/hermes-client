# frozen_string_literal: true

module HermesAgent
  class Client
    ##
    # Base class for lightweight wrappers around parsed JSON payloads.
    #
    # Subclasses add method readers for the fields we have mapped, but the raw
    # parsed payload is always available as the source of truth: {#to_h}
    # returns the full hash and {#[]} reads an individual key.
    #
    class Entity
      ##
      # Wrap a parsed JSON payload.
      #
      # @param data [Hash] The parsed response body, with string keys.
      #
      def initialize(data)
        @data = data
      end

      ##
      # Read a raw field by its server-side (string) key.
      #
      # @param key [String] The field name.
      # @return [Object, nil] The raw value, or `nil` if absent.
      #
      def [](key)
        @data[key]
      end

      ##
      # The full parsed payload.
      #
      # @return [Hash] The raw response body with string keys.
      #
      def to_h
        @data
      end
    end
  end
end
