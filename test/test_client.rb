# frozen_string_literal: true

require "helper"

describe ::HermesAgent::Client do
  it "builds its configuration from keyword arguments" do
    client = ::HermesAgent::Client.new(base_url: "https://example.test", api_key: "secret")
    assert_equal("https://example.test", client.config.base_url)
    assert_equal("secret", client.config.api_key)
  end

  describe "api_key env default (delegated to Configuration)" do
    # Save and restore the env var the api_key default reads from.
    before do
      @saved_api_key = ENV.fetch("HERMES_API_KEY", nil)
    end

    after do
      if @saved_api_key.nil?
        ENV.delete("HERMES_API_KEY")
      else
        ENV["HERMES_API_KEY"] = @saved_api_key
      end
    end

    it "picks up HERMES_API_KEY when api_key is omitted" do
      ENV["HERMES_API_KEY"] = "from-env"
      assert_equal("from-env", ::HermesAgent::Client.new.config.api_key)
    end

    it "sends no key (overriding the env var) when api_key is explicitly nil" do
      ENV["HERMES_API_KEY"] = "from-env"
      assert_nil(::HermesAgent::Client.new(api_key: nil).config.api_key)
    end

    it "uses an explicit api_key over the env var" do
      ENV["HERMES_API_KEY"] = "from-env"
      assert_equal("explicit", ::HermesAgent::Client.new(api_key: "explicit").config.api_key)
    end
  end

  it "yields the configuration to a block for customization" do
    client = ::HermesAgent::Client.new do |config|
      config.base_url = "https://block.test"
    end
    assert_equal("https://block.test", client.config.base_url)
  end

  it "applies the block after keyword arguments" do
    client = ::HermesAgent::Client.new(base_url: "https://kwarg.test") do |config|
      config.base_url = "https://block.test"
    end
    assert_equal("https://block.test", client.config.base_url)
  end

  it "exposes a health resource" do
    client = ::HermesAgent::Client.new
    assert_instance_of(::HermesAgent::Client::Resources::Health, client.health)
  end

  it "memoizes the health resource" do
    client = ::HermesAgent::Client.new
    assert_same(client.health, client.health)
  end

  it "exposes a responses resource" do
    client = ::HermesAgent::Client.new
    assert_instance_of(::HermesAgent::Client::Resources::Responses, client.responses)
  end

  it "memoizes the responses resource" do
    client = ::HermesAgent::Client.new
    assert_same(client.responses, client.responses)
  end
end
