# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "http"

# Support code shared by the `toys gateway` tools: gateway state persistence,
# server-key resolution, process-lifecycle helpers, and raw HTTP/SSE probing
# with prettified JSON output.
#
# This logic deliberately bypasses the client library and talks to the server
# with raw HTTP, so the tools display the server's actual wire format rather
# than whatever the client's entity wrappers would surface.
module HermesGateway
  module_function

  # Path to the gitignored state file describing the running gateway.
  def state_path(context_dir)
    ::File.join(context_dir, "tmp", "gateway-state.json")
  end

  # Path to the gateway's captured stdout/stderr log.
  def log_path(context_dir)
    ::File.join(context_dir, "tmp", "gateway.log")
  end

  # Reads the recorded gateway state, or nil if there is none / it is corrupt.
  def read_state(context_dir)
    path = state_path(context_dir)
    return nil unless ::File.exist?(path)
    ::JSON.parse(::File.read(path))
  rescue ::JSON::ParserError
    nil
  end

  # Writes the gateway state to the gitignored state file.
  def write_state(context_dir, state)
    path = state_path(context_dir)
    ::FileUtils.mkdir_p(::File.dirname(path))
    ::File.write(path, "#{::JSON.pretty_generate(state)}\n")
  end

  # Removes the state file if present.
  def clear_state(context_dir)
    path = state_path(context_dir)
    ::File.delete(path) if ::File.exist?(path)
  end

  # Resolves the server key: an explicit value, else $API_SERVER_KEY, else a
  # freshly generated random key.
  def resolve_key(explicit)
    value = explicit || ::ENV["API_SERVER_KEY"]
    return value unless value.nil? || value.empty?
    ::SecureRandom.hex(24)
  end

  # Whether a process with the given pid is currently alive.
  def process_alive?(pid)
    return false if pid.nil?
    ::Process.kill(0, pid)
    true
  rescue ::Errno::ESRCH
    false
  rescue ::Errno::EPERM
    true
  end

  # Sends SIGINT, waits for the process to exit, and escalates to SIGKILL if it
  # does not stop in time.
  def stop_process(pid)
    ::Process.kill("INT", pid)
    20.times do
      return unless process_alive?(pid)
      sleep(0.25)
    end
    ::Process.kill("KILL", pid)
  rescue ::Errno::ESRCH
    nil
  end

  # Polls GET /health until it reports ok, up to the given number of attempts
  # (one second apart). Returns true once healthy, false if it never responds.
  def wait_for_health(base_url, attempts: 30)
    attempts.times do
      begin
        result = ::HTTP.timeout(2).get("#{base_url}/health")
        return true if result.status.success? && result.body.to_s.include?("ok")
      rescue ::HTTP::Error, ::Errno::ECONNREFUSED, ::SocketError
        # Not up yet; keep waiting.
      end
      sleep(1)
    end
    false
  end

  # Makes a single raw HTTP request to the gateway and renders the response.
  def probe(base_url:, method:, path:, token: nil, body: nil, stream: false,
            session_id: nil, session_key: nil)
    url = "#{base_url.chomp('/')}#{path}"
    client = ::HTTP
    client = client.auth("Bearer #{token}") if token && !token.empty?
    headers = {"Accept" => stream ? "text/event-stream" : "application/json"}
    headers["Content-Type"] = "application/json" if body
    headers["X-Hermes-Session-ID"] = session_id if session_id
    headers["X-Hermes-Session-Key"] = session_key if session_key
    client = client.headers(headers)
    opts = body ? {body: body} : {}
    response = client.request(method.to_s.downcase.to_sym, url, **opts)
    stream ? render_stream(response) : render_response(response)
  end

  # Prints the HTTP status line (to stderr) and the prettified body (to stdout),
  # so that redirecting stdout captures clean JSON.
  def render_response(response)
    $stderr.puts("HTTP #{response.status}")
    render_session_headers(response)
    puts(pretty_json(response.body.to_s))
  end

  # Session response headers worth surfacing while studying conversation
  # continuity. Lookup is case-insensitive via the HTTP gem's header set.
  SESSION_HEADERS = ["X-Hermes-Session-ID", "X-Hermes-Session-Key"].freeze

  # Prints any session-continuity response headers (to stderr, so stdout stays
  # clean JSON). Silent when none are present.
  def render_session_headers(response)
    SESSION_HEADERS.each do |name|
      value = response.headers[name]
      $stderr.puts("#{name}: #{value}") unless value.nil?
    end
  end

  # Reads an SSE response frame-by-frame, printing each event name and its
  # prettified data payload as the frames arrive.
  def render_stream(response)
    $stderr.puts("HTTP #{response.status} (streaming SSE)")
    render_session_headers(response)
    $stdout.sync = true
    body = response.body
    buffer = +""
    begin
      while (chunk = body.readpartial)
        buffer << chunk.to_s.gsub("\r\n", "\n")
        while (idx = buffer.index("\n\n"))
          emit_frame(buffer.slice!(0, idx + 2))
        end
      end
    rescue ::EOFError
      # Normal end of stream.
    end
    emit_frame(buffer) unless buffer.strip.empty?
  ensure
    body.close if body.respond_to?(:close)
  end

  # Renders one SSE frame: its event name (only when the frame carries one),
  # then its data prettified as JSON (or shown raw if the data is not JSON,
  # e.g. the [DONE] sentinel).
  def emit_frame(frame)
    event = nil
    data = []
    frame.each_line(chomp: true) do |line|
      case line
      when /\Aevent:\s?(.*)\z/ then event = ::Regexp.last_match(1)
      when /\Adata:\s?(.*)\z/ then data << ::Regexp.last_match(1)
      end
    end
    payload = data.join("\n")
    return if event.nil? && payload.empty?
    puts("event: #{event}") if event
    puts(pretty_json(payload)) unless payload.empty?
    puts
  end

  # Pretty-prints a JSON string, or returns it unchanged if it is not JSON.
  def pretty_json(text)
    return "" if text.nil? || text.empty?
    ::JSON.pretty_generate(::JSON.parse(text))
  rescue ::JSON::ParserError
    text
  end
end
