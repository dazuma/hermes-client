# frozen_string_literal: true

include :bundler
include "gateway_helpers"

desc "Fetch the gateway health endpoint"

flag :detailed, "--detailed" do
  desc "Request /health/detailed instead of /health"
end

def run
  gateway_probe("GET", detailed ? "/health/detailed" : "/health")
end
