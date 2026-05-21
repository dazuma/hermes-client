# frozen_string_literal: true

require "helper"

describe ::HermesAgent::Client::Entities::Model do
  model_hash = {
    "id" => "hermes-test",
    "object" => "model",
    "created" => 1_779_403_392,
    "owned_by" => "hermes",
    "permission" => [],
    "root" => "hermes-test",
    "parent" => nil,
  }

  it "reads the model fields" do
    model = ::HermesAgent::Client::Entities::Model.new(model_hash)
    assert_equal("hermes-test", model.id)
    assert_equal("model", model.object)
    assert_equal(1_779_403_392, model.created)
    assert_equal("hermes", model.owned_by)
    assert_equal("hermes-test", model.root)
    assert_nil(model.parent)
  end

  it "returns nil for fields when absent" do
    model = ::HermesAgent::Client::Entities::Model.new({})
    assert_nil(model.id)
    assert_nil(model.object)
    assert_nil(model.created)
    assert_nil(model.owned_by)
    assert_nil(model.root)
    assert_nil(model.parent)
  end
end

describe ::HermesAgent::Client::Resources::Models do
  list_payload = {
    "object" => "list",
    "data" => [
      {"id" => "hermes-test", "object" => "model"},
      {"id" => "other-model", "object" => "model"},
    ],
  }

  it "fetches the /v1/models path" do
    transport = ::HermesAgent::Tests::FakeTransport.new(list_payload)
    ::HermesAgent::Client::Resources::Models.new(transport).list
    assert_equal("/v1/models", transport.requested_path)
  end

  it "returns an array of Model entities" do
    transport = ::HermesAgent::Tests::FakeTransport.new(list_payload)
    models = ::HermesAgent::Client::Resources::Models.new(transport).list
    assert_kind_of(::Array, models)
    assert_equal(2, models.length)
    assert_instance_of(::HermesAgent::Client::Entities::Model, models.first)
    assert_equal(["hermes-test", "other-model"], models.map(&:id))
  end

  it "returns an empty array when data is missing" do
    transport = ::HermesAgent::Tests::FakeTransport.new("object" => "list")
    models = ::HermesAgent::Client::Resources::Models.new(transport).list
    assert_equal([], models)
  end

  it "returns an empty array when data is not an array" do
    transport = ::HermesAgent::Tests::FakeTransport.new("data" => "nonsense")
    models = ::HermesAgent::Client::Resources::Models.new(transport).list
    assert_equal([], models)
  end
end

describe "models" do
  integration_port = ENV["HERMES_CLIENT_INTEGRATION_PORT"]

  if integration_port
    let(:client) do
      ::HermesAgent::Client.new(base_url: "http://localhost:#{integration_port}")
    end

    it "lists models from the live gateway" do
      models = client.models.list
      assert_kind_of(::Array, models)
      refute_empty(models)
      first = models.first
      assert_instance_of(::HermesAgent::Client::Entities::Model, first)
      refute_nil(first.id)
      assert_equal("model", first.object)
    end
  end
end
