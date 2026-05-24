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

describe ::HermesAgent::Client::Entities::RunApprovalResponse do
  it "reads the fields" do
    resp = ::HermesAgent::Client::Entities::RunApprovalResponse.new(
      "object" => "hermes.run.approval_response", "run_id" => "run_1", "choice" => "deny", "resolved" => 1
    )
    assert_equal("hermes.run.approval_response", resp.object)
    assert_equal("run_1", resp.run_id)
    assert_equal("deny", resp.choice)
    assert_equal(1, resp.resolved)
  end

  it "returns nil for fields when absent" do
    resp = ::HermesAgent::Client::Entities::RunApprovalResponse.new({})
    assert_nil(resp.object)
    assert_nil(resp.run_id)
    assert_nil(resp.choice)
    assert_nil(resp.resolved)
  end
end

describe ::HermesAgent::Client::Resources::Runs do
  let(:transport) do
    ::HermesAgent::Tests::FakeTransport.new("run_id" => "run_1", "status" => "started")
  end
  let(:stop_transport) do
    ::HermesAgent::Tests::FakeTransport.new("run_id" => "run_1", "status" => "stopping")
  end
  let(:approval_transport) do
    ::HermesAgent::Tests::FakeTransport.new(
      "object" => "hermes.run.approval_response", "run_id" => "run_1", "choice" => "deny", "resolved" => 1
    )
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

  it "posts to the /v1/runs/{id}/approval path with the choice" do
    ::HermesAgent::Client::Resources::Runs.new(approval_transport).respond_approval("run_1", choice: "deny")
    assert_equal("/v1/runs/run_1/approval", approval_transport.requested_path)
    assert_equal("deny", approval_transport.requested_body[:choice])
  end

  it "wraps the approval response in a RunApprovalResponse entity" do
    resp = ::HermesAgent::Client::Resources::Runs.new(approval_transport).respond_approval("run_1", choice: "deny")
    assert_instance_of(::HermesAgent::Client::Entities::RunApprovalResponse, resp)
    assert_equal("hermes.run.approval_response", resp.object)
    assert_equal("deny", resp.choice)
    assert_equal(1, resp.resolved)
  end
end

describe ::HermesAgent::Client::Entities::RunEvent do
  it "reads the common envelope fields" do
    event = ::HermesAgent::Client::Entities::RunEvent.new(
      "event" => "message.delta", "run_id" => "run_1", "timestamp" => 1_779_510_796.5
    )
    assert_equal("message.delta", event.event)
    assert_equal("run_1", event.run_id)
    assert_in_delta(1_779_510_796.5, event.timestamp)
  end

  it "reads a tool.started event" do
    event = ::HermesAgent::Client::Entities::RunEvent.new(
      "event" => "tool.started", "tool" => "terminal", "preview" => "sleep 10"
    )
    assert_equal("terminal", event.tool)
    assert_equal("sleep 10", event.preview)
  end

  it "reads a tool.completed event, including the error result flag" do
    event = ::HermesAgent::Client::Entities::RunEvent.new(
      "event" => "tool.completed", "tool" => "terminal", "duration" => 0.42, "error" => false
    )
    assert_equal("terminal", event.tool)
    assert_in_delta(0.42, event.duration)
    assert_equal(false, event.error?)
  end

  it "reads a message.delta event" do
    event = ::HermesAgent::Client::Entities::RunEvent.new("event" => "message.delta", "delta" => "Hel")
    assert_equal("Hel", event.delta)
  end

  it "reads a reasoning.available event" do
    event = ::HermesAgent::Client::Entities::RunEvent.new("event" => "reasoning.available", "text" => "because")
    assert_equal("because", event.text)
  end

  it "reads a run.completed event, wrapping usage in a RunUsage" do
    event = ::HermesAgent::Client::Entities::RunEvent.new(
      "event" => "run.completed", "output" => "Hello",
      "usage" => {"input_tokens" => 10, "output_tokens" => 1, "total_tokens" => 11}
    )
    assert_equal("Hello", event.output)
    assert_instance_of(::HermesAgent::Client::Entities::RunUsage, event.usage)
    assert_equal(11, event.usage.total_tokens)
  end

  it "reads an approval.request event" do
    event = ::HermesAgent::Client::Entities::RunEvent.new(
      "event" => "approval.request", "command" => "rm -rf /tmp/x", "pattern_key" => "rm",
      "pattern_keys" => ["rm", "rm_rf"], "description" => "Delete files",
      "choices" => ["once", "session", "always", "deny"]
    )
    assert_equal("rm -rf /tmp/x", event.command)
    assert_equal("rm", event.pattern_key)
    assert_equal(["rm", "rm_rf"], event.pattern_keys)
    assert_equal("Delete files", event.description)
    assert_equal(["once", "session", "always", "deny"], event.choices)
  end

  it "reads an approval.responded event" do
    event = ::HermesAgent::Client::Entities::RunEvent.new("event" => "approval.responded", "choice" => "deny",
                                                          "resolved" => 1)
    assert_equal("deny", event.choice)
    assert_equal(1, event.resolved)
  end

  it "returns nil for fields when absent" do
    event = ::HermesAgent::Client::Entities::RunEvent.new({})
    assert_nil(event.event)
    assert_nil(event.usage)
    assert_nil(event.output)
    assert_nil(event.tool)
    assert_nil(event.error?)
    assert_nil(event.pattern_keys)
    assert_nil(event.choices)
  end

  describe ".terminal" do
    it "returns the last run.* lifecycle event" do
      events = [
        ::HermesAgent::Client::Entities::RunEvent.new("event" => "message.delta", "delta" => "Hi"),
        ::HermesAgent::Client::Entities::RunEvent.new("event" => "run.completed", "output" => "Hi"),
      ]
      terminal = ::HermesAgent::Client::Entities::RunEvent.terminal(events)
      assert_equal("run.completed", terminal.event)
      assert_equal("Hi", terminal.output)
    end

    it "returns nil when no run.* event is present" do
      events = [::HermesAgent::Client::Entities::RunEvent.new("event" => "message.delta", "delta" => "Hi")]
      assert_nil(::HermesAgent::Client::Entities::RunEvent.terminal(events))
    end
  end
end

describe "Resources::Runs#stream_events" do
  def frame(hash)
    "data: #{::JSON.generate(hash)}\n\n"
  end

  let(:stream_chunks) do
    [
      frame("event" => "message.delta", "run_id" => "run_1", "timestamp" => 1.0, "delta" => "Hel"),
      frame("event" => "message.delta", "run_id" => "run_1", "timestamp" => 1.1, "delta" => "lo"),
      frame("event" => "run.completed", "run_id" => "run_1", "timestamp" => 2.0, "output" => "Hello",
            "usage" => {"input_tokens" => 10, "output_tokens" => 1, "total_tokens" => 11}),
    ]
  end
  let(:transport) { ::HermesAgent::Tests::FakeTransport.new({}, stream_chunks) }

  it "gets the run's events path" do
    ::HermesAgent::Client::Resources::Runs.new(transport).stream_events("run_1").result
    assert_equal("/v1/runs/run_1/events", transport.requested_path)
  end

  it "yields RunEvent events and returns the terminal event (block form)" do
    deltas = []
    terminal = ::HermesAgent::Client::Resources::Runs.new(transport).stream_events("run_1") do |event|
      assert_instance_of(::HermesAgent::Client::Entities::RunEvent, event)
      deltas << event.delta if event.delta
    end
    assert_equal(["Hel", "lo"], deltas)
    assert_instance_of(::HermesAgent::Client::Entities::RunEvent, terminal)
    assert_equal("run.completed", terminal.event)
    assert_equal("Hello", terminal.output)
    assert_equal(11, terminal.usage.total_tokens)
  end

  it "returns a Stream the caller can iterate (enumerator form)" do
    stream = ::HermesAgent::Client::Resources::Runs.new(transport).stream_events("run_1")
    assert_instance_of(::HermesAgent::Client::Stream, stream)
    text = stream.each.filter_map(&:delta).join
    assert_equal("Hello", text)
    assert_equal("run.completed", stream.result.event)
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
    # progresses in the background. Poll get until the yielded run satisfies the
    # given condition (or time out), so the assertions can inspect it.
    def poll_until(run_id, timeout: 30.0, interval: 0.5)
      deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + timeout
      loop do
        run = client.runs.get(run_id)
        return run if yield(run)
        if ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) > deadline
          flunk("run #{run_id} did not satisfy the poll condition within #{timeout}s (last: #{run.status})")
        end
        sleep(interval)
      end
    end

    TERMINAL_STATUSES = ["completed", "cancelled", "failed"].freeze

    def poll_until_terminal(run_id, **)
      poll_until(run_id, **) { |run| TERMINAL_STATUSES.include?(run.status) }
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

    it "streams a run's events to completion against the live gateway" do
      created = client.runs.create(input: "Say hello in exactly two words.")
      events = []
      terminal = client.runs.stream_events(created.run_id) do |event|
        assert_instance_of(::HermesAgent::Client::Entities::RunEvent, event)
        events << event
      end
      refute_empty(events)
      assert_instance_of(::HermesAgent::Client::Entities::RunEvent, terminal)
      assert_equal("run.completed", terminal.event)
      refute_empty(terminal.output)
      assert_instance_of(::HermesAgent::Client::Entities::RunUsage, terminal.usage)
      assert_operator(terminal.usage.total_tokens, :>, 0)
    end

    it "raises NotFoundError when getting an unknown run id" do
      assert_raises(::HermesAgent::Client::NotFoundError) do
        client.runs.get("run_#{'0' * 32}")
      end
    end

    # The approval gate only fires when the gateway profile is in
    # `approvals.mode: manual` with a non-container backend (hermes-test is).
    # `rm -rf /tmp/<throwaway>` matches the recursive-delete dangerous pattern
    # but is harmless even if executed, and is not on the hardline blocklist.
    APPROVAL_TRIGGER = "Please run the shell command 'rm -rf /tmp/hermes_client_approval_probe' in the terminal."

    it "denies a parked approval, and the run still completes" do
      created = client.runs.create(input: APPROVAL_TRIGGER)
      parked = poll_until(created.run_id) { |run| run.status == "waiting_for_approval" }
      assert_equal("waiting_for_approval", parked.status)

      resp = client.runs.respond_approval(created.run_id, choice: "deny")
      assert_instance_of(::HermesAgent::Client::Entities::RunApprovalResponse, resp)
      assert_equal("hermes.run.approval_response", resp.object)
      assert_equal(created.run_id, resp.run_id)
      assert_equal("deny", resp.choice)
      assert_operator(resp.resolved, :>=, 1)

      # Deny is not a failure: the agent aborts the command but the run resolves
      # to completed.
      run = poll_until_terminal(created.run_id)
      assert_equal("completed", run.status)
    end

    # Approving actually EXECUTES the gated command, so this is opt-in: a tester
    # sets HERMES_CLIENT_INTEGRATION_APPROVE to run it. Uses `once` (no config
    # mutation, unlike `always`/`session`) against a throwaway /tmp path.
    if ENV["HERMES_CLIENT_INTEGRATION_APPROVE"]
      it "approves a parked approval with once, and the run completes" do
        created = client.runs.create(input: APPROVAL_TRIGGER)
        parked = poll_until(created.run_id) { |run| run.status == "waiting_for_approval" }
        assert_equal("waiting_for_approval", parked.status)

        resp = client.runs.respond_approval(created.run_id, choice: "once")
        assert_instance_of(::HermesAgent::Client::Entities::RunApprovalResponse, resp)
        assert_equal("once", resp.choice)
        assert_operator(resp.resolved, :>=, 1)

        run = poll_until_terminal(created.run_id)
        assert_equal("completed", run.status)
      end
    end
  end
end
