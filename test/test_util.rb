# frozen_string_literal: true

require "helper"

describe ::HermesAgent::Client::Util do
  describe ".parse_json" do
    it "parses valid JSON" do
      assert_equal({"a" => 1}, ::HermesAgent::Client::Util.parse_json('{"a":1}'))
    end

    it "raises MalformedResponseError carrying the text on invalid JSON" do
      error = assert_raises(::HermesAgent::Client::MalformedResponseError) do
        ::HermesAgent::Client::Util.parse_json("not json{")
      end
      assert_equal("not json{", error.body)
    end
  end
end
