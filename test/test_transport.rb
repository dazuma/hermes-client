# frozen_string_literal: true

require "helper"
require "webmock"

describe ::HermesAgent::Client::Transport do
  include ::WebMock::API

  # Confine WebMock to this file so it does not interfere with the integration
  # gateway, which makes real localhost requests.
  before do
    ::WebMock.enable!
    ::WebMock.disable_net_connect!
  end

  after do
    ::WebMock.reset!
    ::WebMock.disable!
  end

  def transport(**)
    ::HermesAgent::Client::Transport.new(::HermesAgent::Client::Configuration.new(**))
  end

  it "parses a JSON response body" do
    stub_request(:get, "https://example.test/health")
      .to_return(status: 200, body: '{"status":"ok"}')
    result = transport(base_url: "https://example.test").get("/health")
    assert_equal({"status" => "ok"}, result)
  end

  it "returns an empty hash for an empty body" do
    stub_request(:get, "https://example.test/health").to_return(status: 200, body: "")
    assert_equal({}, transport(base_url: "https://example.test").get("/health"))
  end

  it "sends a bearer Authorization header when an api_key is set" do
    stub = stub_request(:get, "https://example.test/health")
           .with(headers: {"Authorization" => "Bearer secret"})
           .to_return(status: 200, body: "{}")
    transport(base_url: "https://example.test", api_key: "secret").get("/health")
    assert_requested(stub)
  end

  it "omits the Authorization header when no api_key is set" do
    stub_request(:get, "https://example.test/health").to_return(status: 200, body: "{}")
    transport(base_url: "https://example.test", api_key: nil).get("/health")
    assert_requested(:get, "https://example.test/health") do |req|
      assert_nil(req.headers["Authorization"])
    end
  end

  it "posts a JSON body and parses the JSON response" do
    stub = stub_request(:post, "https://example.test/v1/chat/completions")
           .with(headers: {"Content-Type" => %r{application/json}}, body: '{"messages":[]}')
           .to_return(status: 200, body: '{"object":"chat.completion"}')
    result = transport(base_url: "https://example.test").post("/v1/chat/completions", {messages: []})
    assert_equal({"object" => "chat.completion"}, result)
    assert_requested(stub)
  end

  it "sends the bearer Authorization header on a post" do
    stub = stub_request(:post, "https://example.test/v1/chat/completions")
           .with(headers: {"Authorization" => "Bearer secret"})
           .to_return(status: 200, body: "{}")
    transport(base_url: "https://example.test", api_key: "secret").post("/v1/chat/completions", {messages: []})
    assert_requested(stub)
  end

  it "maps a post error response to the status-mapped APIError" do
    body = '{"error":{"message":"Invalid API key","type":"invalid_request_error","code":"invalid_api_key"}}'
    stub_request(:post, "https://example.test/v1/chat/completions").to_return(status: 401, body: body)
    error = assert_raises(::HermesAgent::Client::AuthenticationError) do
      transport(base_url: "https://example.test").post("/v1/chat/completions", {messages: []})
    end
    assert_equal("Invalid API key", error.message)
  end

  it "stream_post returns a body that yields the response chunks" do
    stub_request(:post, "https://example.test/v1/chat/completions")
      .to_return(status: 200, body: "data: {\"n\":1}\n\n")
    body = transport(base_url: "https://example.test").stream_post("/v1/chat/completions", {messages: []})
    assert_equal("data: {\"n\":1}\n\n", body.to_a.join)
  end

  it "stream_post raises a status-mapped APIError before streaming on an error response" do
    stub_request(:post, "https://example.test/v1/chat/completions")
      .to_return(status: 401, body: '{"error":{"message":"Invalid API key"}}')
    assert_raises(::HermesAgent::Client::AuthenticationError) do
      transport(base_url: "https://example.test").stream_post("/v1/chat/completions", {messages: []})
    end
  end

  it "issues a DELETE and parses the JSON response" do
    stub = stub_request(:delete, "https://example.test/v1/responses/resp_1")
           .to_return(status: 200, body: '{"id":"resp_1","object":"response","deleted":true}')
    result = transport(base_url: "https://example.test").delete("/v1/responses/resp_1")
    assert_equal({"id" => "resp_1", "object" => "response", "deleted" => true}, result)
    assert_requested(stub)
  end

  it "sends the bearer Authorization header on a delete" do
    stub = stub_request(:delete, "https://example.test/v1/responses/resp_1")
           .with(headers: {"Authorization" => "Bearer secret"})
           .to_return(status: 200, body: "{}")
    transport(base_url: "https://example.test", api_key: "secret").delete("/v1/responses/resp_1")
    assert_requested(stub)
  end

  it "maps a delete error response to the status-mapped APIError" do
    body = '{"error":{"message":"Response not found: resp_x","type":"invalid_request_error"}}'
    stub_request(:delete, "https://example.test/v1/responses/resp_x").to_return(status: 404, body: body)
    error = assert_raises(::HermesAgent::Client::NotFoundError) do
      transport(base_url: "https://example.test").delete("/v1/responses/resp_x")
    end
    assert_equal("Response not found: resp_x", error.message)
  end

  it "joins base_url and path without a doubled slash" do
    stub = stub_request(:get, "https://example.test/health").to_return(status: 200, body: "{}")
    transport(base_url: "https://example.test/").get("/health")
    assert_requested(stub)
  end

  it "raises a status-mapped APIError carrying the status and body" do
    stub_request(:get, "https://example.test/health")
      .to_return(status: 503, body: "down for maintenance")
    error = assert_raises(::HermesAgent::Client::ServerError) do
      transport(base_url: "https://example.test").get("/health")
    end
    assert_equal(503, error.status)
    assert_equal("down for maintenance", error.body)
  end

  it "parses a structured error payload onto the raised error" do
    body = '{"error":{"message":"Invalid API key","type":"invalid_request_error",' \
           '"code":"invalid_api_key"}}'
    stub_request(:get, "https://example.test/health").to_return(status: 401, body: body)
    error = assert_raises(::HermesAgent::Client::AuthenticationError) do
      transport(base_url: "https://example.test").get("/health")
    end
    assert_equal("Invalid API key", error.message)
    assert_equal("invalid_api_key", error.error["code"])
  end

  it "maps an HTTP timeout to TimeoutError" do
    stub_request(:get, "https://example.test/health").to_raise(::HTTP::TimeoutError)
    assert_raises(::HermesAgent::Client::TimeoutError) do
      transport(base_url: "https://example.test").get("/health")
    end
  end

  it "maps a connection failure to ConnectionError" do
    stub_request(:get, "https://example.test/health").to_raise(::HTTP::ConnectionError)
    assert_raises(::HermesAgent::Client::ConnectionError) do
      transport(base_url: "https://example.test").get("/health")
    end
  end
end
