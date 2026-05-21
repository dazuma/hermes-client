# frozen_string_literal: true

require "securerandom"

require "minitest/autorun"
require "minitest/focus"
require "minitest/rg"

require "hermes-client"

module HermesAgent
  # Shared support code for the test suite.
  module Tests
    # The API key the integration gateway is launched with (and that
    # authenticated integration clients should send), or nil when integration
    # tests are not running.
    class << self
      attr_accessor :integration_api_key

      # Launch the integration gateway (with a generated API key) when the
      # integration environment variables are set, polling until it is healthy
      # and registering its shutdown. A no-op when they are not set.
      def start_integration_gateway
        port = ::ENV["HERMES_CLIENT_INTEGRATION_PORT"]
        profile = ::ENV["HERMES_CLIENT_INTEGRATION_PROFILE"]
        return unless port && profile

        require "exec_service"
        puts "Starting test gateway on port #{port}"
        self.integration_api_key = ::SecureRandom.hex(24)
        cmd = ["hermes", "-p", profile, "gateway", "run"]
        env = {"API_SERVER_PORT" => port, "API_SERVER_KEY" => integration_api_key}
        gateway = ::ExecService.new.exec(cmd, background: true, env: env)
        puts "Launched test gateway with PID=#{gateway.pid}"
        puts(gateway_responding?(port) ? "Test gateway is responding" : "WARNING: Test gateway not responding")
        register_shutdown(gateway)
      end

      private

      # Poll the gateway's /health until it responds ok, up to five tries.
      def gateway_responding?(port)
        5.times do
          sleep 1
          result = ::HTTP.get("http://localhost:#{port}/health")
          return true if result.code == 200 && result.body.to_s.include?("ok")
        rescue ::HTTP::Error
          # just try again
        end
        false
      end

      # Tear the gateway down after the suite finishes.
      def register_shutdown(gateway)
        ::Minitest.after_run do
          puts "Terminating test gateway"
          gateway.kill("SIGINT")
          gateway.result
          puts "Test gateway is down"
        end
      end
    end

    # A stand-in for Transport in unit tests: it records the path (and, for
    # #post, the body) it was asked for and returns a canned payload instead of
    # making a real HTTP request.
    class FakeTransport
      def initialize(response = {}, stream_chunks = [])
        @response = response
        @stream_chunks = stream_chunks
      end

      # The path passed to the most recent request.
      attr_reader :requested_path

      # The body passed to the most recent #post / #stream_post call.
      attr_reader :requested_body

      def get(path)
        @requested_path = path
        @response
      end

      def post(path, body)
        @requested_path = path
        @requested_body = body
        @response
      end

      def stream_post(path, body)
        @requested_path = path
        @requested_body = body
        @stream_chunks
      end
    end
  end
end

::HermesAgent::Tests.start_integration_gateway
