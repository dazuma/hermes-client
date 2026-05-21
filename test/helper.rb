# frozen_string_literal: true

require "minitest/autorun"
require "minitest/focus"
require "minitest/rg"

require "hermes-client"

hermes_port = ENV["HERMES_CLIENT_INTEGRATION_PORT"]
hermes_profile = ENV["HERMES_CLIENT_INTEGRATION_PROFILE"]
if hermes_port && hermes_profile
  require "exec_service"
  puts "Starting test gateway on port #{hermes_port}"
  cmd = ["hermes", "-p", hermes_profile, "gateway", "run"]
  env = {"API_SERVER_PORT" => hermes_port}
  test_gateway = ::ExecService.new.exec(cmd, background: true, env: env)
  puts "Launched test gateway with PID=#{test_gateway.pid}"
  ok = false
  5.times do
    sleep 1
    result = ::HTTP.get("http://localhost:#{hermes_port}/health")
    if result.code == 200 && result.body.to_s.include?("ok")
      ok = true
      break
    end
  rescue HTTP::Error => e
    # just try again
  end
  if ok
    puts "Test gateway is responding"
  else
    puts "WARNING: Test gateway not responding"
  end
  ::Minitest.after_run do
    puts "Terminating test gateway"
    test_gateway.kill("SIGINT")
    test_gateway.result
    puts "Test gateway is down"
  end
end
