# frozen_string_literal: true

include :bundler
include "gateway_helpers"

desc "Send a prompt to the Responses API (POST /v1/responses)"

long_desc \
  "Posts the given input text to the Responses API, which persists " \
    "conversation state server-side, and prints the prettified response. Chain " \
    "turns with --previous (a prior response id) or --conversation (a named " \
    "conversation). Use --stream to receive the response as SSE."

required_arg :text do
  desc "The input text"
end
flag :previous, "--previous=ID" do
  desc "previous_response_id to chain onto a prior response"
end
flag :conversation, "--conversation=NAME" do
  desc "A named conversation to chain turns within"
end
flag :stream, "--stream" do
  desc "Stream the response as SSE"
end

def run
  require "json"
  payload = {"input" => text}
  payload["previous_response_id"] = previous if previous
  payload["conversation"] = conversation if conversation
  payload["stream"] = true if stream
  gateway_probe("POST", "/v1/responses", body: ::JSON.generate(payload), stream: stream)
end
