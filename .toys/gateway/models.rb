# frozen_string_literal: true

include :bundler
include "gateway_helpers"

desc "Fetch GET /v1/models from the running gateway"

def run
  gateway_probe("GET", "/v1/models")
end
