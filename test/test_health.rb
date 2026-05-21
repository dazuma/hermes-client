# frozen_string_literal: true

require "helper"

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
