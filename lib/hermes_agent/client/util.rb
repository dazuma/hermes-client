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
