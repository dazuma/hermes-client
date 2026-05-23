# frozen_string_literal: true

include :bundler
include "gateway_helpers"

desc "Make a raw HTTP request to the running gateway and print the response"

long_desc \
  "Sends a raw HTTP request (bypassing the client wrappers) to the running " \
    "gateway and prints the prettified JSON response body. The bearer token is " \
    "drawn from the running gateway's recorded key. The HTTP status line goes " \
    "to stderr, so redirecting stdout captures clean JSON.",
  "",
  "With --stream the response is read as Server-Sent Events: each frame's event " \
    "name is printed, followed by its data payload prettified as JSON (or shown " \
    "raw if it is not JSON, e.g. the [DONE] sentinel).",
  "",
  "Examples:",
  ["    toys gateway probe GET /v1/models"],
  ["    toys gateway probe POST /v1/responses --body '{\"input\":\"hi\"}'"],
  ["    toys gateway probe POST /v1/chat/completions --body '...' --stream"]

required_arg :verb do
  desc "HTTP method: GET, POST, PATCH, or DELETE"
end
required_arg :path do
  desc "Request path, e.g. /v1/models"
end
flag :body, "--body=JSON" do
  desc "Request body, as a JSON string"
end
flag :stream, "--stream" do
  desc "Read the response as an SSE stream and render each frame"
end
flag :token, "--token=TOKEN" do
  desc "Override the bearer token (default: the running gateway's key)"
end
flag :session_id, "--session-id=ID" do
  desc "Send an X-Hermes-Session-ID request header"
end
flag :session_key, "--session-key=KEY" do
  desc "Send an X-Hermes-Session-Key request header"
end

def run
  gateway_probe(verb, path, body: body, stream: stream, token: token,
                session_id: session_id, session_key: session_key)
end
