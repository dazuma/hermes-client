# frozen_string_literal: true

desc "Stop the local Hermes test gateway"

def run
  require "hermes_gateway"
  state = HermesGateway.read_state(context_directory)
  if state.nil?
    puts("No gateway state recorded; nothing to stop.")
    return
  end
  pid = state["pid"]
  if HermesGateway.process_alive?(pid)
    puts("Stopping gateway (pid #{pid})...")
    HermesGateway.stop_process(pid)
    puts("Gateway stopped.")
  else
    puts("Gateway (pid #{pid}) was not running.")
  end
  HermesGateway.clear_state(context_directory)
end
