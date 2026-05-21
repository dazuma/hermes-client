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

  it "joins base_url and path without a doubled slash" do
    stub = stub_request(:get, "https://example.test/health").to_return(status: 200, body: "{}")
    transport(base_url: "https://example.test/").get("/health")
    assert_requested(stub)
  end

  it "raises APIError carrying the status and body on a non-2xx response" do
    stub_request(:get, "https://example.test/health")
      .to_return(status: 503, body: "down for maintenance")
    error = assert_raises(::HermesAgent::Client::APIError) do
      transport(base_url: "https://example.test").get("/health")
    end
    assert_equal(503, error.status)
    assert_equal("down for maintenance", error.body)
  end
end
