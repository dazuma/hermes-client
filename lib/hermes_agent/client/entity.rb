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
    # Entities are immutable value objects: both the entity and its underlying
    # payload are frozen on construction, and equality ({#==} / {#eql?} /
    # {#hash}) is by class and payload, so entities can be compared and used as
    # Hash keys.
    #
    class Entity
      ##
      # Wrap a parsed JSON payload. The payload and the entity are frozen.
      #
      # @param data [Hash] The parsed response body, with string keys.
      #
      def initialize(data)
        @data = data.freeze
        freeze
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
      # The full parsed payload (frozen).
      #
      # @return [Hash] The raw response body with string keys.
      #
      def to_h
        @data
      end

      ##
      # Whether this entity equals another: true when `other` is an instance of
      # the same class wrapping equal payload data.
      #
      # @param other [Object] The object to compare against.
      # @return [boolean]
      #
      def ==(other)
        other.instance_of?(self.class) && other.to_h == @data
      end

      ##
      # Alias of {#==}, so entities behave consistently as Hash keys (paired
      # with {#hash}).
      #
      # @param other [Object] The object to compare against.
      # @return [boolean]
      #
      def eql?(other)
        self == other
      end

      ##
      # A hash code consistent with {#==} and {#eql?}.
      #
      # @return [Integer]
      #
      def hash
        [self.class, @data].hash
      end
    end
  end
end
