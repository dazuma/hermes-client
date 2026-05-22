# frozen_string_literal: true

require "helper"

describe ::HermesAgent::Client do
  it "builds its configuration from keyword arguments" do
    client = ::HermesAgent::Client.new(base_url: "https://example.test", api_key: "secret")
    assert_equal("https://example.test", client.config.base_url)
    assert_equal("secret", client.config.api_key)
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
