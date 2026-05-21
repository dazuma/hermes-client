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

describe ::HermesAgent::Client::Entities::PlatformStatus do
  it "reads the per-platform fields" do
    status = ::HermesAgent::Client::Entities::PlatformStatus.new(
      "state" => "connected",
      "error_code" => nil,
      "error_message" => nil,
      "updated_at" => "2026-05-21T21:13:33.042491+00:00"
    )
    assert_equal("connected", status.state)
    assert_nil(status.error_code)
    assert_nil(status.error_message)
    assert_equal("2026-05-21T21:13:33.042491+00:00", status.updated_at)
  end

  it "returns nil for fields when absent" do
    status = ::HermesAgent::Client::Entities::PlatformStatus.new({})
    assert_nil(status.state)
    assert_nil(status.error_code)
    assert_nil(status.error_message)
    assert_nil(status.updated_at)
  end
end

describe ::HermesAgent::Client::Entities::HealthDetails do
  detailed = {
    "status" => "ok",
    "platform" => "hermes-agent",
    "gateway_state" => "running",
    "platforms" => {
      "api_server" => {
        "state" => "connected",
        "error_code" => nil,
        "error_message" => nil,
        "updated_at" => "2026-05-21T21:13:33.042491+00:00",
      },
    },
    "active_agents" => 2,
    "exit_reason" => nil,
    "updated_at" => "2026-05-21T21:13:33.042909+00:00",
    "pid" => 38_293,
  }

  it "is independent of the Health entity" do
    refute_operator(::HermesAgent::Client::Entities::HealthDetails, :<,
                    ::HermesAgent::Client::Entities::Health)
  end

  it "reads the scalar detailed fields" do
    health = ::HermesAgent::Client::Entities::HealthDetails.new(detailed)
    assert_equal("ok", health.status)
    assert_equal("hermes-agent", health.platform)
    assert_equal("running", health.gateway_state)
    assert_equal(2, health.active_agents)
    assert_nil(health.exit_reason)
    assert_equal("2026-05-21T21:13:33.042909+00:00", health.updated_at)
    assert_equal(38_293, health.pid)
  end

  it "wraps each platform value in a PlatformStatus entity" do
    health = ::HermesAgent::Client::Entities::HealthDetails.new(detailed)
    platforms = health.platforms
    assert_kind_of(::Hash, platforms)
    assert_equal(["api_server"], platforms.keys)
    api_server = platforms["api_server"]
    assert_instance_of(::HermesAgent::Client::Entities::PlatformStatus, api_server)
    assert_equal("connected", api_server.state)
  end

  it "exposes the raw platforms hash via to_h" do
    health = ::HermesAgent::Client::Entities::HealthDetails.new(detailed)
    assert_equal("connected", health.to_h["platforms"]["api_server"]["state"])
  end

  it "returns nil for detailed fields when absent" do
    health = ::HermesAgent::Client::Entities::HealthDetails.new({})
    assert_nil(health.status)
    assert_nil(health.platform)
    assert_nil(health.gateway_state)
    assert_nil(health.platforms)
    assert_nil(health.active_agents)
    assert_nil(health.updated_at)
    assert_nil(health.pid)
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

  it "fetches the /health/detailed path" do
    ::HermesAgent::Client::Resources::Health.new(transport).detailed
    assert_equal("/health/detailed", transport.requested_path)
  end

  it "wraps the detailed response in a HealthDetails entity" do
    health = ::HermesAgent::Client::Resources::Health.new(transport).detailed
    assert_instance_of(::HermesAgent::Client::Entities::HealthDetails, health)
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

    it "reports detailed status from the live gateway" do
      health = client.health.detailed
      assert_equal("ok", health.status)
      refute_nil(health.gateway_state)
      assert_kind_of(::Integer, health.active_agents)
      api_server = health.platforms["api_server"]
      assert_instance_of(::HermesAgent::Client::Entities::PlatformStatus, api_server)
    end
  end
end
