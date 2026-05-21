# frozen_string_literal: true

include :bundler
include "gateway_helpers"

desc "Fetch GET /v1/capabilities from the running gateway"

def run
  gateway_probe("GET", "/v1/capabilities")
end
