# frozen_string_literal: true

require "json"

require "hermes_agent/client/errors"

module HermesAgent
  class Client
    ##
    # Internal helpers shared across the client's layers. Not part of the
    # public API.
    #
    module Util
      ##
      # The downcased response-header name carrying the session id.
      #
      SESSION_ID_HEADER = "x-hermes-session-id"

      ##
      # The downcased response-header name carrying the session key.
      #
      SESSION_KEY_HEADER = "x-hermes-session-key"

      ##
      # Extract the session-continuity values from a normalized (downcased-key)
      # response-header hash into the keyword form the session-bearing entities
      # ({Entities::ChatCompletion}, {Entities::Response}) accept. Either value
      # is `nil` when the corresponding header is absent.
      #
      # @param headers [Hash{String=>String}] Response headers, keyed by
      #     downcased name (as produced by {Transport}).
      # @return [Hash{Symbol=>(String, nil)}] `{session_id:, session_key:}`.
      #
      def self.session_headers(headers)
        {session_id: headers[SESSION_ID_HEADER], session_key: headers[SESSION_KEY_HEADER]}
      end

      ##
      # Parse JSON from a payload the client expected to be JSON, mapping a
      # parse failure to {MalformedResponseError} so a raw `JSON::ParserError`
      # never leaks out. Shared by the non-streaming ({Transport#handle}) and
      # streaming ({Stream#dispatch}) paths so the two behave identically.
      #
      # @param text [String] The raw text to parse.
      # @return [Object] The parsed JSON value.
      # @raise [MalformedResponseError] If the text is not valid JSON.
      #
      def self.parse_json(text)
        ::JSON.parse(text)
      rescue ::JSON::ParserError
        raise MalformedResponseError.new("Invalid JSON in response body", body: text)
      end
    end
  end
end
