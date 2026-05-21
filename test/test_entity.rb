# frozen_string_literal: true

require "helper"

describe ::HermesAgent::Client::Entity do
  let(:data) { {"status" => "ok", "count" => 3} }
  let(:entity) { ::HermesAgent::Client::Entity.new(data) }

  it "returns the full payload from to_h" do
    assert_equal(data, entity.to_h)
  end

  it "reads a raw field by string key" do
    assert_equal("ok", entity["status"])
    assert_equal(3, entity["count"])
  end

  it "returns nil for an absent key" do
    assert_nil(entity["missing"])
  end
end
