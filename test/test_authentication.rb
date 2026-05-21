# frozen_string_literal: true

require "helper"

# End-to-end authentication behavior against a live gateway launched with an
# API key (see test/helper.rb). Uses discovery endpoints (cheap, no LLM call)
# to exercise the auth path.
describe "authentication" do
  integration_port = ENV["HERMES_CLIENT_INTEGRATION_PORT"]

  if integration_port
    base_url = "http://localhost:#{integration_port}"

    def client(base_url, api_key)
      ::HermesAgent::Client.new(base_url: base_url, api_key: api_key)
    end

    it "accepts a request carrying the correct api key" do
      models = client(base_url, ::HermesAgent::Tests.integration_api_key).models.list
      refute_empty(models)
    end

    it "rejects a request carrying a wrong api key" do
      assert_raises(::HermesAgent::Client::AuthenticationError) do
        client(base_url, "definitely-not-the-key").models.list
      end
    end

    it "rejects a request carrying no api key on an auth-required endpoint" do
      assert_raises(::HermesAgent::Client::AuthenticationError) do
        client(base_url, nil).models.list
      end
    end

    it "allows health checks without an api key" do
      assert_equal("ok", client(base_url, nil).health.check.status)
    end
  end
end
