# frozen_string_literal: true

require "helper"

describe ::HermesAgent::Client::Configuration do
  let(:config_class) { ::HermesAgent::Client::Configuration }

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

  it "defaults base_url to the server root" do
    ENV.delete("HERMES_API_KEY")
    config = config_class.new
    assert_equal("http://127.0.0.1:8642", config.base_url)
  end

  it "defaults timeouts to nil" do
    config = config_class.new
    assert_nil(config.timeout)
    assert_nil(config.open_timeout)
    assert_nil(config.write_timeout)
  end

  it "defaults keep_alive_timeout to 5 seconds" do
    config = config_class.new
    assert_equal(5, config.keep_alive_timeout)
  end

  it "defaults api_key to nil when HERMES_API_KEY is unset" do
    ENV.delete("HERMES_API_KEY")
    config = config_class.new
    assert_nil(config.api_key)
  end

  it "defaults api_key from the HERMES_API_KEY environment variable" do
    ENV["HERMES_API_KEY"] = "from-env"
    config = config_class.new
    assert_equal("from-env", config.api_key)
  end

  it "lets keyword arguments override the defaults" do
    config = config_class.new(base_url: "https://example.test",
                              api_key: "secret",
                              timeout: 30,
                              open_timeout: 5,
                              write_timeout: 10,
                              keep_alive_timeout: 60)
    assert_equal("https://example.test", config.base_url)
    assert_equal("secret", config.api_key)
    assert_equal(30, config.timeout)
    assert_equal(5, config.open_timeout)
    assert_equal(10, config.write_timeout)
    assert_equal(60, config.keep_alive_timeout)
  end

  it "exposes mutable accessors" do
    config = config_class.new
    config.base_url = "https://changed.test"
    config.api_key = "new-key"
    config.keep_alive_timeout = 90
    assert_equal("https://changed.test", config.base_url)
    assert_equal("new-key", config.api_key)
    assert_equal(90, config.keep_alive_timeout)
  end
end
