# frozen_string_literal: true

require "helper"

describe "version constant" do
  it "is set" do
    assert(defined?(::HermesAgent::Client::VERSION))
  end
end
