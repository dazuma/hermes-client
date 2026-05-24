# frozen_string_literal: true

require "helper"

describe ::HermesAgent::Client::Entities::RunUsage do
  it "reads the token counts" do
    usage = ::HermesAgent::Client::Entities::RunUsage.new(
      "input_tokens" => 14_010, "output_tokens" => 1, "total_tokens" => 14_011
    )
    assert_equal(14_010, usage.input_tokens)
    assert_equal(1, usage.output_tokens)
    assert_equal(14_011, usage.total_tokens)
  end

  it "returns nil for fields when absent" do
    usage = ::HermesAgent::Client::Entities::RunUsage.new({})
    assert_nil(usage.input_tokens)
    assert_nil(usage.output_tokens)
    assert_nil(usage.total_tokens)
  end
end

describe ::HermesAgent::Client::Entities::Run do
  let(:completed_run) do
    {
      "object" => "hermes.run",
      "run_id" => "run_0591466636124693b94936a2314f20e5",
      "status" => "completed",
      "updated_at" => 1_779_510_798.6846,
      "created_at" => 1_779_510_796.504134,
      "session_id" => "run_0591466636124693b94936a2314f20e5",
      "model" => "hermes-test",
      "last_event" => "run.completed",
      "output" => "hello",
      "usage" => {"input_tokens" => 14_010, "output_tokens" => 1, "total_tokens" => 14_011},
    }
  end
  # The minimal shape returned by create (HTTP 202): only run_id + status.
  let(:created_run) do
    {"run_id" => "run_0591466636124693b94936a2314f20e5", "status" => "started"}
  end
  # The shape after a stop resolves: output and usage are absent.
  let(:cancelled_run) do
    {
      "object" => "hermes.run",
      "run_id" => "run_0591466636124693b94936a2314f20e5",
      "status" => "cancelled",
      "last_event" => "run.cancelled",
    }
  end

  it "reads the scalar fields" do
    run = ::HermesAgent::Client::Entities::Run.new(completed_run)
    assert_equal("hermes.run", run.object)
    assert_equal("run_0591466636124693b94936a2314f20e5", run.run_id)
    assert_equal("completed", run.status)
    assert_in_delta(1_779_510_796.504134, run.created_at)
    assert_in_delta(1_779_510_798.6846, run.updated_at)
    assert_equal("run_0591466636124693b94936a2314f20e5", run.session_id)
    assert_equal("hermes-test", run.model)
    assert_equal("run.completed", run.last_event)
    assert_equal("hello", run.output)
  end

  it "aliases id to run_id" do
    run = ::HermesAgent::Client::Entities::Run.new(completed_run)
    assert_equal(run.run_id, run.id)
  end

  it "wraps usage in a RunUsage" do
    run = ::HermesAgent::Client::Entities::Run.new(completed_run)
    assert_instance_of(::HermesAgent::Client::Entities::RunUsage, run.usage)
    assert_equal(14_011, run.usage.total_tokens)
  end

  it "tolerates the minimal create shape" do
    run = ::HermesAgent::Client::Entities::Run.new(created_run)
    assert_equal("run_0591466636124693b94936a2314f20e5", run.run_id)
    assert_equal("started", run.status)
    assert_nil(run.output)
    assert_nil(run.usage)
  end

  it "returns nil for output and usage when absent (e.g. cancelled)" do
    run = ::HermesAgent::Client::Entities::Run.new(cancelled_run)
    assert_nil(run.output)
    assert_nil(run.usage)
  end
end

describe ::HermesAgent::Client::Entities::RunStop do
  it "reads the run_id and status" do
    ack = ::HermesAgent::Client::Entities::RunStop.new("run_id" => "run_1", "status" => "stopping")
    assert_equal("run_1", ack.run_id)
    assert_equal("stopping", ack.status)
  end

  it "returns nil for fields when absent" do
    ack = ::HermesAgent::Client::Entities::RunStop.new({})
    assert_nil(ack.run_id)
    assert_nil(ack.status)
  end
end

describe ::HermesAgent::Client::Resources::Runs do
  let(:transport) do
    ::HermesAgent::Tests::FakeTransport.new("run_id" => "run_1", "status" => "started")
  end
  let(:stop_transport) do
    ::HermesAgent::Tests::FakeTransport.new("run_id" => "run_1", "status" => "stopping")
  end

  it "posts to the /v1/runs path" do
    ::HermesAgent::Client::Resources::Runs.new(transport).create(input: "hello")
    assert_equal("/v1/runs", transport.requested_path)
  end

  it "sends the input in the request body" do
    ::HermesAgent::Client::Resources::Runs.new(transport).create(input: "hello")
    assert_equal("hello", transport.requested_body[:input])
  end

  it "does not send a model field" do
    ::HermesAgent::Client::Resources::Runs.new(transport).create(input: "hello")
    refute(transport.requested_body.key?(:model))
  end

  it "omits the optional fields when not given" do
    ::HermesAgent::Client::Resources::Runs.new(transport).create(input: "hello")
    refute(transport.requested_body.key?(:instructions))
    refute(transport.requested_body.key?(:conversation_history))
    refute(transport.requested_body.key?(:previous_response_id))
    refute(transport.requested_body.key?(:session_id))
  end

  it "sends instructions when given" do
    ::HermesAgent::Client::Resources::Runs.new(transport).create(input: "hi", instructions: "be terse")
    assert_equal("be terse", transport.requested_body[:instructions])
  end

  it "sends conversation_history when given" do
    history = [{"role" => "user", "content" => "earlier"}]
    ::HermesAgent::Client::Resources::Runs.new(transport).create(input: "hi", conversation_history: history)
    assert_equal(history, transport.requested_body[:conversation_history])
  end

  it "sends previous_response_id when chaining a stored response" do
    ::HermesAgent::Client::Resources::Runs.new(transport).create(input: "hi", previous_response_id: "resp_0")
    assert_equal("resp_0", transport.requested_body[:previous_response_id])
  end

  it "sends session_id when given" do
    ::HermesAgent::Client::Resources::Runs.new(transport).create(input: "hi", session_id: "sess-1")
    assert_equal("sess-1", transport.requested_body[:session_id])
  end

  it "merges extra keyword arguments into the body" do
    ::HermesAgent::Client::Resources::Runs.new(transport).create(input: "hi", temperature: 0.2)
    assert_in_delta(0.2, transport.requested_body[:temperature])
  end

  it "wraps the create response in a Run entity" do
    run = ::HermesAgent::Client::Resources::Runs.new(transport).create(input: "hello")
    assert_instance_of(::HermesAgent::Client::Entities::Run, run)
    assert_equal("run_1", run.run_id)
    assert_equal("started", run.status)
  end

  it "gets a run by id and wraps it in a Run entity" do
    getter = ::HermesAgent::Tests::FakeTransport.new("run_id" => "run_1", "status" => "completed")
    run = ::HermesAgent::Client::Resources::Runs.new(getter).get("run_1")
    assert_equal("/v1/runs/run_1", getter.requested_path)
    assert_instance_of(::HermesAgent::Client::Entities::Run, run)
    assert_equal("completed", run.status)
  end

  it "posts to the /v1/runs/{id}/stop path" do
    ::HermesAgent::Client::Resources::Runs.new(stop_transport).stop("run_1")
    assert_equal("/v1/runs/run_1/stop", stop_transport.requested_path)
  end

  it "wraps the stop response in a RunStop entity" do
    ack = ::HermesAgent::Client::Resources::Runs.new(stop_transport).stop("run_1")
    assert_instance_of(::HermesAgent::Client::Entities::RunStop, ack)
    assert_equal("run_1", ack.run_id)
    assert_equal("stopping", ack.status)
  end
end

describe "runs" do
  it "is reachable from the client" do
    client = ::HermesAgent::Client.new(base_url: "http://127.0.0.1:8642")
    assert_instance_of(::HermesAgent::Client::Resources::Runs, client.runs)
  end

  integration_port = ENV["HERMES_CLIENT_INTEGRATION_PORT"]

  if integration_port
    let(:client) do
      ::HermesAgent::Client.new(base_url: "http://localhost:#{integration_port}",
                                api_key: ::HermesAgent::Tests.integration_api_key)
    end

    # A run is server-side asynchronous: create returns immediately and the run
    # progresses in the background. Poll get until it reaches a terminal status
    # (or time out), so the assertions can inspect the finished run.
    def poll_until_terminal(run_id, timeout: 30.0, interval: 0.5)
      terminal = ["completed", "cancelled", "failed"]
      deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + timeout
      loop do
        run = client.runs.get(run_id)
        return run if terminal.include?(run.status)
        if ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) > deadline
          flunk("run #{run_id} did not reach a terminal status within #{timeout}s (last: #{run.status})")
        end
        sleep(interval)
      end
    end

    it "creates a run and polls it to completion against the live gateway" do
      created = client.runs.create(input: "Say hello in exactly two words.")
      assert_instance_of(::HermesAgent::Client::Entities::Run, created)
      # Create returns immediately with the minimal accepted run.
      refute_nil(created.run_id)
      assert_equal(created.run_id, created.id)
      assert_equal("started", created.status)

      run = poll_until_terminal(created.run_id)
      assert_equal(created.run_id, run.run_id)
      assert_equal("hermes.run", run.object)
      assert_equal("completed", run.status)
      assert_equal("run.completed", run.last_event)
      refute_empty(run.output)
      assert_instance_of(::HermesAgent::Client::Entities::RunUsage, run.usage)
      assert_operator(run.usage.total_tokens, :>, 0)
    end

    it "stops a run against the live gateway, resolving it to cancelled" do
      # Induce a single `sleep` terminal tool call: it holds the run alive for
      # a deterministic window while burning wall-clock, not tokens, so an
      # immediate stop reliably lands mid-run at near-zero cost. `sleep` is not
      # an approval-gated command.
      created = client.runs.create(
        input: "Please run the shell command 'sleep 10' in the terminal, then tell me it finished."
      )
      ack = client.runs.stop(created.run_id)
      assert_instance_of(::HermesAgent::Client::Entities::RunStop, ack)
      assert_equal(created.run_id, ack.run_id)
      assert_equal("stopping", ack.status)

      # Stop is cooperative: the run then resolves to a terminal cancelled.
      run = poll_until_terminal(created.run_id)
      assert_equal("cancelled", run.status)
    end

    it "raises NotFoundError when getting an unknown run id" do
      assert_raises(::HermesAgent::Client::NotFoundError) do
        client.runs.get("run_#{'0' * 32}")
      end
    end
  end
end
