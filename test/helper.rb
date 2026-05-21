# frozen_string_literal: true

require "minitest/autorun"
require "minitest/focus"
require "minitest/rg"

require "hermes-client"

module HermesAgent
  # Shared support code for the test suite.
  module Tests
    # A stand-in for Transport in unit tests: it records the path it was asked
    # for and returns a canned payload instead of making a real HTTP request.
    class FakeTransport
      def initialize(response = {})
        @response = response
      end

      # The path passed to the most recent #get call.
      attr_reader :requested_path

      def get(path)
        @requested_path = path
        @response
      end
    end
  end
end

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
  rescue HTTP::Error
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
