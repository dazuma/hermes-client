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

  describe "missing or non-Hash payload" do
    it "coerces a nil payload to an empty hash so readers return nil cleanly" do
      entity = ::HermesAgent::Client::Entity.new(nil)
      assert_equal({}, entity.to_h)
      assert_nil(entity["anything"])
      assert_predicate(entity, :frozen?)
    end

    it "keeps a non-nil, non-Hash payload as-is (the streaming path wraps arrays)" do
      entity = ::HermesAgent::Client::Entity.new([1, 2])
      assert_equal([1, 2], entity.to_h)
    end
  end

  describe "immutability" do
    it "freezes the entity and its payload" do
      assert_predicate(entity, :frozen?)
      assert_predicate(entity.to_h, :frozen?)
    end
  end

  describe "equality" do
    it "is equal to a same-class instance wrapping equal data" do
      other = ::HermesAgent::Client::Entity.new({"status" => "ok", "count" => 3})
      assert_equal(entity, other)
      assert(entity.eql?(other))
      assert_equal(entity.hash, other.hash)
    end

    it "differs from an instance wrapping different data" do
      other = ::HermesAgent::Client::Entity.new({"status" => "ok"})
      refute_equal(entity, other)
    end

    it "differs from an instance of another class with equal data" do
      subclass = ::Class.new(::HermesAgent::Client::Entity)
      other = subclass.new({"status" => "ok", "count" => 3})
      refute_equal(entity, other)
    end

    it "works as a hash key" do
      table = {entity => "value"}
      lookup = ::HermesAgent::Client::Entity.new({"status" => "ok", "count" => 3})
      assert_equal("value", table[lookup])
    end
  end
end
