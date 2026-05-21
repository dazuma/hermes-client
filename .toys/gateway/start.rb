# frozen_string_literal: true

include :bundler

desc "Start a local Hermes test gateway in the background"

long_desc \
  "Spawns `hermes -p <profile> gateway run` as a detached background process, " \
    "waits for /health to report ok, and records the pid, port, profile, base " \
    "URL, and server key in tmp/gateway-state.json so the probe tools can reach " \
    "it.",
  "",
  "The server key is taken from --key, else the API_SERVER_KEY environment " \
    "variable, else a freshly generated random key. Whatever is used is recorded " \
    "in the state file so probes authenticate automatically."

flag :profile, "--profile=PROFILE", default: "hermes-test" do
  desc "The hermes profile to run (default: hermes-test)"
end
flag :port, "--port=PORT", default: "10099" do
  desc "The port to run the gateway on (default: 10099)"
end
flag :key, "--key=KEY" do
  desc "The server API key (default: $API_SERVER_KEY, or a generated key)"
end

def run
  require "hermes_gateway"
  existing = HermesGateway.read_state(context_directory)
  if existing && HermesGateway.process_alive?(existing["pid"])
    $stderr.puts("A gateway is already running (pid #{existing['pid']}, port #{existing['port']}).")
    $stderr.puts("Stop it first with `toys gateway stop`.")
    exit(1)
  end

  server_key = HermesGateway.resolve_key(key)
  log = HermesGateway.log_path(context_directory)
  ::FileUtils.mkdir_p(::File.dirname(log))

  cmd = ["hermes", "-p", profile, "gateway", "run"]
  env = {"API_SERVER_PORT" => port.to_s, "API_SERVER_KEY" => server_key}
  $stderr.puts("Starting: #{cmd.join(' ')} (port #{port}, profile #{profile})")
  pid = ::Process.spawn(env, *cmd, out: [log, "w"], err: [:child, :out])
  ::Process.detach(pid)

  base_url = "http://127.0.0.1:#{port}"
  HermesGateway.write_state(context_directory,
                            "pid" => pid,
                            "port" => port.to_i,
                            "profile" => profile,
                            "base_url" => base_url,
                            "key" => server_key)

  if HermesGateway.wait_for_health(base_url)
    $stderr.puts("Gateway is up: #{base_url} (pid #{pid}). Logs: #{log}")
  else
    $stderr.puts("WARNING: gateway did not become healthy. Check #{log}.")
    exit(1)
  end
end
