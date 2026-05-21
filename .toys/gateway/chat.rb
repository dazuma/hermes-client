# frozen_string_literal: true

include :bundler
include "gateway_helpers"

desc "Send a chat completion (POST /v1/chat/completions) to the gateway"

long_desc \
  "Wraps the given text as a single user message and posts it to the " \
    "OpenAI-compatible chat completions endpoint, printing the prettified " \
    "response. Use --stream to receive the completion as SSE."

required_arg :text do
  desc "The user message content"
end
flag :stream, "--stream" do
  desc "Stream the completion as SSE"
end

def run
  payload = {"messages" => [{"role" => "user", "content" => text}]}
  payload["stream"] = true if stream
  gateway_probe("POST", "/v1/chat/completions", body: ::JSON.generate(payload), stream: stream)
end
