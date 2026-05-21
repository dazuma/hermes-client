# frozen_string_literal: true

desc "Run and probe a local Hermes test gateway"

long_desc \
  "Tools to spin up a local Hermes gateway in the background, probe its " \
    "endpoints with raw HTTP, and display prettified JSON (and raw SSE frames) " \
    "so we can inspect the actual response data the server returns. The probes " \
    "deliberately bypass the client library to show the unvarnished wire format.",
  "",
  "Typical flow: `toys gateway start`, then probe with `toys gateway probe ...` " \
    "or one of the endpoint shortcuts (models, capabilities, health, chat, " \
    "respond), then `toys gateway stop` when done."

mixin "gateway_helpers" do
  # Load the shared support library once, at execution time, when the `.lib`
  # directory is on the load path. Tools that include this mixin therefore do
  # not need their own requires.
  on_initialize do
    require "hermes_gateway"
  end

  # Returns the recorded state of the running gateway, or aborts the tool with
  # a helpful message if none is running.
  def running_state
    state = HermesGateway.read_state(context_directory)
    if state.nil? || !HermesGateway.process_alive?(state["pid"])
      $stderr.puts("No running gateway. Start one with `toys gateway start`.")
      exit(1)
    end
    state
  end

  # Probes the running gateway, drawing the base URL and bearer token from its
  # recorded state.
  def gateway_probe(method, path, body: nil, stream: false, token: nil)
    state = running_state
    HermesGateway.probe(
      base_url: state["base_url"],
      token: token || state["key"],
      method: method,
      path: path,
      body: body,
      stream: stream
    )
  end
end
