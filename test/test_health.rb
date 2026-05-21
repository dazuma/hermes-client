# frozen_string_literal: true

require "helper"

describe ::HermesAgent::Client::Entities::Health do
  it "reads the status field" do
    health = ::HermesAgent::Client::Entities::Health.new({"status" => "ok"})
    assert_equal("ok", health.status)
  end

  it "returns nil when the status field is absent" do
    health = ::HermesAgent::Client::Entities::Health.new({})
    assert_nil(health.status)
  end
end

describe ::HermesAgent::Client::Resources::Health do
  let(:transport) { ::HermesAgent::Tests::FakeTransport.new({"status" => "ok"}) }

  it "checks the root /health path" do
    ::HermesAgent::Client::Resources::Health.new(transport).check
    assert_equal("/health", transport.requested_path)
  end

  it "wraps the response in a Health entity" do
    health = ::HermesAgent::Client::Resources::Health.new(transport).check
    assert_instance_of(::HermesAgent::Client::Entities::Health, health)
    assert_equal("ok", health.status)
  end
end

describe "health" do
  integration_port = ENV["HERMES_CLIENT_INTEGRATION_PORT"]

  if integration_port
    let(:client) do
      ::HermesAgent::Client.new(base_url: "http://localhost:#{integration_port}")
    end

    it "reports an ok status from the live gateway" do
      health = client.health.check
      assert_equal("ok", health.status)
    end

    it "exposes the raw payload via to_h" do
      health = client.health.check
      assert_equal("ok", health.to_h["status"])
    end
  end
end
