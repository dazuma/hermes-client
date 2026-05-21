# frozen_string_literal: true

include "gateway_helpers"

desc "Show whether the local Hermes test gateway is running"

def run
  state = HermesGateway.read_state(context_directory)
  if state.nil?
    puts("No gateway state recorded; not running.")
    exit(1)
  end
  alive = HermesGateway.process_alive?(state["pid"])
  puts("status:   #{alive ? 'running' : 'not running (stale state)'}")
  puts("pid:      #{state['pid']}")
  puts("port:     #{state['port']}")
  puts("profile:  #{state['profile']}")
  puts("base_url: #{state['base_url']}")
  exit(1) unless alive
end
