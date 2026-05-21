# frozen_string_literal: true

require "helper"

describe ::HermesAgent::Client::Entities::Auth do
  it "reads the auth fields" do
    auth = ::HermesAgent::Client::Entities::Auth.new("type" => "bearer", "required" => true)
    assert_equal("bearer", auth.type)
    assert_equal(true, auth.required)
  end

  it "returns nil for fields when absent" do
    auth = ::HermesAgent::Client::Entities::Auth.new({})
    assert_nil(auth.type)
    assert_nil(auth.required)
  end
end

describe ::HermesAgent::Client::Entities::Runtime do
  it "reads the runtime fields" do
    runtime = ::HermesAgent::Client::Entities::Runtime.new(
      "mode" => "server_agent",
      "tool_execution" => "server",
      "split_runtime" => false,
      "description" => "The API server creates a server-side Hermes AIAgent."
    )
    assert_equal("server_agent", runtime.mode)
    assert_equal("server", runtime.tool_execution)
    assert_equal(false, runtime.split_runtime)
    assert_equal("The API server creates a server-side Hermes AIAgent.", runtime.description)
  end

  it "returns nil for fields when absent" do
    runtime = ::HermesAgent::Client::Entities::Runtime.new({})
    assert_nil(runtime.mode)
    assert_nil(runtime.tool_execution)
    assert_nil(runtime.split_runtime)
    assert_nil(runtime.description)
  end
end

describe ::HermesAgent::Client::Entities::Features do
  features_hash = {
    "chat_completions" => true,
    "chat_completions_streaming" => true,
    "responses_api" => true,
    "responses_streaming" => true,
    "run_submission" => true,
    "run_status" => true,
    "run_events_sse" => true,
    "run_stop" => true,
    "run_approval_response" => true,
    "tool_progress_events" => true,
    "approval_events" => true,
    "cors" => false,
    "session_continuity_header" => "X-Hermes-Session-Id",
    "session_key_header" => "X-Hermes-Session-Key",
  }

  it "reads each boolean feature flag" do
    features = ::HermesAgent::Client::Entities::Features.new(features_hash)
    assert_equal(true, features.chat_completions)
    assert_equal(true, features.chat_completions_streaming)
    assert_equal(true, features.responses_api)
    assert_equal(true, features.responses_streaming)
    assert_equal(true, features.run_submission)
    assert_equal(true, features.run_status)
    assert_equal(true, features.run_events_sse)
    assert_equal(true, features.run_stop)
    assert_equal(true, features.run_approval_response)
    assert_equal(true, features.tool_progress_events)
    assert_equal(true, features.approval_events)
    assert_equal(false, features.cors)
  end

  it "reads the session header names" do
    features = ::HermesAgent::Client::Entities::Features.new(features_hash)
    assert_equal("X-Hermes-Session-Id", features.session_continuity_header)
    assert_equal("X-Hermes-Session-Key", features.session_key_header)
  end

  it "returns nil for features when absent" do
    features = ::HermesAgent::Client::Entities::Features.new({})
    assert_nil(features.chat_completions)
    assert_nil(features.cors)
    assert_nil(features.session_continuity_header)
    assert_nil(features.session_key_header)
  end
end

describe ::HermesAgent::Client::Entities::Endpoint do
  it "reads the method and path, exposing method as http_method" do
    endpoint = ::HermesAgent::Client::Entities::Endpoint.new("method" => "GET", "path" => "/v1/models")
    assert_equal("GET", endpoint.http_method)
    assert_equal("/v1/models", endpoint.path)
  end

  it "does not shadow Object#method" do
    endpoint = ::HermesAgent::Client::Entities::Endpoint.new("method" => "GET", "path" => "/v1/models")
    assert_kind_of(::Method, endpoint.method(:path))
  end

  it "returns nil for fields when absent" do
    endpoint = ::HermesAgent::Client::Entities::Endpoint.new({})
    assert_nil(endpoint.http_method)
    assert_nil(endpoint.path)
  end
end

describe ::HermesAgent::Client::Entities::Capabilities do
  payload = {
    "object" => "hermes.api_server.capabilities",
    "platform" => "hermes-agent",
    "model" => "hermes-test",
    "auth" => {"type" => "bearer", "required" => true},
    "runtime" => {"mode" => "server_agent", "tool_execution" => "server", "split_runtime" => false},
    "features" => {"chat_completions" => true, "cors" => false},
    "endpoints" => {
      "models" => {"method" => "GET", "path" => "/v1/models"},
      "runs" => {"method" => "POST", "path" => "/v1/runs"},
    },
  }

  it "reads the scalar fields" do
    caps = ::HermesAgent::Client::Entities::Capabilities.new(payload)
    assert_equal("hermes.api_server.capabilities", caps.object)
    assert_equal("hermes-agent", caps.platform)
    assert_equal("hermes-test", caps.model)
  end

  it "wraps auth in an Auth entity" do
    caps = ::HermesAgent::Client::Entities::Capabilities.new(payload)
    assert_instance_of(::HermesAgent::Client::Entities::Auth, caps.auth)
    assert_equal("bearer", caps.auth.type)
  end

  it "wraps runtime in a Runtime entity" do
    caps = ::HermesAgent::Client::Entities::Capabilities.new(payload)
    assert_instance_of(::HermesAgent::Client::Entities::Runtime, caps.runtime)
    assert_equal("server_agent", caps.runtime.mode)
  end

  it "wraps features in a Features entity" do
    caps = ::HermesAgent::Client::Entities::Capabilities.new(payload)
    assert_instance_of(::HermesAgent::Client::Entities::Features, caps.features)
    assert_equal(true, caps.features.chat_completions)
  end

  it "wraps each endpoint value in an Endpoint entity, keyed by name" do
    caps = ::HermesAgent::Client::Entities::Capabilities.new(payload)
    endpoints = caps.endpoints
    assert_kind_of(::Hash, endpoints)
    assert_equal(["models", "runs"], endpoints.keys)
    assert_instance_of(::HermesAgent::Client::Entities::Endpoint, endpoints["runs"])
    assert_equal("/v1/runs", endpoints["runs"].path)
    assert_equal("POST", endpoints["runs"].http_method)
  end

  it "exposes the raw payload via to_h" do
    caps = ::HermesAgent::Client::Entities::Capabilities.new(payload)
    assert_equal("/v1/models", caps.to_h["endpoints"]["models"]["path"])
  end

  it "returns nil for fields when absent" do
    caps = ::HermesAgent::Client::Entities::Capabilities.new({})
    assert_nil(caps.object)
    assert_nil(caps.platform)
    assert_nil(caps.model)
    assert_nil(caps.auth)
    assert_nil(caps.runtime)
    assert_nil(caps.features)
    assert_nil(caps.endpoints)
  end
end

describe ::HermesAgent::Client::Resources::Capabilities do
  let(:transport) do
    ::HermesAgent::Tests::FakeTransport.new("object" => "hermes.api_server.capabilities")
  end

  it "fetches the /v1/capabilities path" do
    ::HermesAgent::Client::Resources::Capabilities.new(transport).get
    assert_equal("/v1/capabilities", transport.requested_path)
  end

  it "wraps the response in a Capabilities entity" do
    caps = ::HermesAgent::Client::Resources::Capabilities.new(transport).get
    assert_instance_of(::HermesAgent::Client::Entities::Capabilities, caps)
    assert_equal("hermes.api_server.capabilities", caps.object)
  end
end

describe "capabilities" do
  integration_port = ENV["HERMES_CLIENT_INTEGRATION_PORT"]

  if integration_port
    let(:client) do
      ::HermesAgent::Client.new(base_url: "http://localhost:#{integration_port}")
    end

    it "advertises capabilities from the live gateway" do
      caps = client.capabilities.get
      assert_equal("hermes.api_server.capabilities", caps.object)
      assert_equal("bearer", caps.auth.type)
      refute_nil(caps.runtime.mode)
      assert_equal(true, caps.features.chat_completions)
      models = caps.endpoints["models"]
      assert_instance_of(::HermesAgent::Client::Entities::Endpoint, models)
      assert_equal("/v1/models", models.path)
    end
  end
end
