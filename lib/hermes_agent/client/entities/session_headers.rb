# frozen_string_literal: true

require "hermes_agent/client/entity"

module HermesAgent
  class Client
    module Entities
      ##
      # Mixin for entities that carry the server's session-continuity headers
      # (`X-Hermes-Session-ID` / `X-Hermes-Session-Key`) alongside their JSON
      # body. Included by the entities returned from endpoints that surface
      # those headers ({ChatCompletion}, {Response}).
      #
      # The session values come from response *headers*, not the JSON body, so
      # they are stored separately from the wrapped payload: {Entity#to_h} and
      # {Entity#[]} continue to reflect only the body. They do, however,
      # participate in equality ({#==} / `#eql?`) and {#hash}, so two entities
      # with the same body but different sessions are not equal.
      #
      module SessionHeaders
        ##
        # Wrap a parsed JSON payload, plus the session headers from the response
        # that produced it.
        #
        # @param data [Hash] The parsed response body, with string keys.
        # @param session_id [String, nil] The `X-Hermes-Session-ID` header
        #     value, or `nil` if the response did not carry one.
        # @param session_key [String, nil] The `X-Hermes-Session-Key` header
        #     value, or `nil` if the response did not carry one.
        #
        # @private
        def initialize(data, session_id: nil, session_key: nil)
          @session_id = session_id
          @session_key = session_key
          super(data)
        end

        ##
        # The session id from the response's `X-Hermes-Session-ID` header. The
        # server always returns one (generating a fresh id when the request did
        # not supply a session), except where the endpoint omits the header
        # entirely (e.g. retrieving a response by id), in which case it is `nil`.
        # @return [String, nil]
        #
        attr_reader :session_id

        ##
        # The session key from the response's `X-Hermes-Session-Key` header.
        # Present only when a session key was supplied on the request;
        # otherwise `nil`.
        # @return [String, nil]
        #
        attr_reader :session_key

        ##
        # Whether this entity equals another: same class, equal body payload,
        # and equal session id/key.
        #
        # @param other [Object] The object to compare against.
        # @return [boolean]
        #
        def ==(other)
          super && other.session_id == @session_id && other.session_key == @session_key
        end

        ##
        # A hash code consistent with {#==} and `#eql?`, incorporating the
        # session values.
        #
        # @return [Integer]
        #
        def hash
          [super, @session_id, @session_key].hash
        end
      end
    end
  end
end
