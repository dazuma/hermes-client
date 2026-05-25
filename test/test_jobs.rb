# frozen_string_literal: true

require "helper"

describe ::HermesAgent::Client::Entities::JobRepeat do
  it "reads times and completed" do
    repeat = ::HermesAgent::Client::Entities::JobRepeat.new("times" => 2, "completed" => 1)
    assert_equal(2, repeat.times)
    assert_equal(1, repeat.completed)
  end

  it "tolerates an unbounded (null times) repeat" do
    repeat = ::HermesAgent::Client::Entities::JobRepeat.new("times" => nil, "completed" => 3)
    assert_nil(repeat.times)
    assert_equal(3, repeat.completed)
  end

  it "returns nil for fields when absent" do
    repeat = ::HermesAgent::Client::Entities::JobRepeat.new({})
    assert_nil(repeat.times)
    assert_nil(repeat.completed)
  end
end

describe ::HermesAgent::Client::Entities::JobSchedule do
  let(:once) { ::HermesAgent::Client::Entities::JobSchedule.new("kind" => "once", "run_at" => "2027-02-03T14:00:00", "display" => "once at 2027-02-03 14:00") }
  let(:interval) { ::HermesAgent::Client::Entities::JobSchedule.new("kind" => "interval", "minutes" => 120, "display" => "every 120m") }
  let(:cron) { ::HermesAgent::Client::Entities::JobSchedule.new("kind" => "cron", "expr" => "0 9 * * *", "display" => "0 9 * * *") }

  it "reads the kind and display" do
    assert_equal("once", once.kind)
    assert_equal("once at 2027-02-03 14:00", once.display)
  end

  it "answers the kind predicates for a once schedule" do
    assert(once.once?)
    refute(once.interval?)
    refute(once.cron?)
  end

  it "answers the kind predicates for an interval schedule" do
    refute(interval.once?)
    assert(interval.interval?)
    refute(interval.cron?)
  end

  it "answers the kind predicates for a cron schedule" do
    refute(cron.once?)
    refute(cron.interval?)
    assert(cron.cron?)
  end

  it "exposes run_at on a once schedule" do
    assert_equal("2027-02-03T14:00:00", once.run_at)
  end

  it "exposes minutes on an interval schedule" do
    assert_equal(120, interval.minutes)
  end

  it "exposes expr on a cron schedule" do
    assert_equal("0 9 * * *", cron.expr)
  end

  it "returns nil for payload readers not of the current kind" do
    assert_nil(once.minutes)
    assert_nil(once.expr)
    assert_nil(interval.run_at)
    assert_nil(interval.expr)
    assert_nil(cron.run_at)
    assert_nil(cron.minutes)
  end

  it "returns nil for fields when absent" do
    schedule = ::HermesAgent::Client::Entities::JobSchedule.new({})
    assert_nil(schedule.kind)
    assert_nil(schedule.display)
    refute(schedule.once?)
    refute(schedule.interval?)
    refute(schedule.cron?)
  end
end

describe ::HermesAgent::Client::Entities::Job do
  # The full entity shape observed against hermes-test (devdocs).
  let(:job_hash) do
    {
      "id" => "0ec925dc7192",
      "name" => "Hello world",
      "prompt" => "Say \"hello world\" in a creative way.",
      "skills" => [],
      "skill" => nil,
      "model" => nil,
      "provider" => nil,
      "base_url" => nil,
      "script" => nil,
      "no_agent" => false,
      "context_from" => nil,
      "schedule" => {"kind" => "cron", "expr" => "0 9 * * *", "display" => "0 9 * * *"},
      "schedule_display" => "0 9 * * *",
      "repeat" => {"times" => nil, "completed" => 2},
      "enabled" => true,
      "state" => "scheduled",
      "paused_at" => nil,
      "paused_reason" => nil,
      "created_at" => "2026-05-22T11:51:06.929692-07:00",
      "next_run_at" => "2026-05-25T09:00:00-07:00",
      "last_run_at" => "2026-05-24T09:00:27.846643-07:00",
      "last_status" => "ok",
      "last_error" => nil,
      "last_delivery_error" => nil,
      "deliver" => "local",
      "origin" => nil,
      "enabled_toolsets" => nil,
      "workdir" => nil,
      "profile" => nil,
    }
  end
  let(:job) { ::HermesAgent::Client::Entities::Job.new(job_hash) }

  it "reads the identity and prompt fields" do
    assert_equal("0ec925dc7192", job.id)
    assert_equal("Hello world", job.name)
    assert_equal("Say \"hello world\" in a creative way.", job.prompt)
  end

  it "reads the skills and skill slots" do
    assert_equal([], job.skills)
    assert_nil(job.skill)
  end

  it "reads the read-only override slots" do
    assert_nil(job.model)
    assert_nil(job.provider)
    assert_nil(job.base_url)
    assert_nil(job.workdir)
    assert_nil(job.profile)
    assert_nil(job.context_from)
  end

  it "reads the script slot and the no_agent boolean" do
    assert_nil(job.script)
    assert_equal(false, job.no_agent?)
  end

  it "wraps schedule in a JobSchedule" do
    assert_instance_of(::HermesAgent::Client::Entities::JobSchedule, job.schedule)
    assert_equal("cron", job.schedule.kind)
    assert_equal("0 9 * * *", job.schedule.expr)
  end

  it "reads schedule_display" do
    assert_equal("0 9 * * *", job.schedule_display)
  end

  it "wraps repeat in a JobRepeat" do
    assert_instance_of(::HermesAgent::Client::Entities::JobRepeat, job.repeat)
    assert_nil(job.repeat.times)
    assert_equal(2, job.repeat.completed)
  end

  it "reads the enabled boolean and state" do
    assert_equal(true, job.enabled?)
    assert_equal("scheduled", job.state)
  end

  it "reads the pause fields" do
    assert_nil(job.paused_at)
    assert_nil(job.paused_reason)
  end

  it "exposes timestamps verbatim as ISO-8601 strings" do
    assert_equal("2026-05-22T11:51:06.929692-07:00", job.created_at)
    assert_equal("2026-05-25T09:00:00-07:00", job.next_run_at)
    assert_equal("2026-05-24T09:00:27.846643-07:00", job.last_run_at)
  end

  it "reads the last-run outcome fields" do
    assert_equal("ok", job.last_status)
    assert_nil(job.last_error)
    assert_nil(job.last_delivery_error)
  end

  it "reads the failed last-run outcome fields" do
    # A failed agent run: last_status flips to "error" and last_error carries
    # the exception-prefixed message; a recurring job stays scheduled (verified
    # live 2026-05-24 against hermes-test).
    failed = ::HermesAgent::Client::Entities::Job.new(
      "state" => "scheduled",
      "last_status" => "error",
      "last_error" => "RuntimeError: Gemini HTTP 400 (INVALID_ARGUMENT): API key not valid. " \
                      "Please pass a valid API key.",
      "last_delivery_error" => nil
    )
    assert_equal("error", failed.last_status)
    assert_equal(
      "RuntimeError: Gemini HTTP 400 (INVALID_ARGUMENT): API key not valid. Please pass a valid API key.",
      failed.last_error
    )
    assert_nil(failed.last_delivery_error)
    assert_equal("scheduled", failed.state)
  end

  it "reads the delivery target" do
    assert_equal("local", job.deliver)
  end

  it "passes origin and enabled_toolsets through raw" do
    assert_nil(job.origin)
    assert_nil(job.enabled_toolsets)
  end

  it "exposes a populated origin and enabled_toolsets verbatim" do
    populated = ::HermesAgent::Client::Entities::Job.new(
      "origin" => {"channel" => "telegram"}, "enabled_toolsets" => ["terminal", "search_files"]
    )
    assert_equal({"channel" => "telegram"}, populated.origin)
    assert_equal(["terminal", "search_files"], populated.enabled_toolsets)
  end

  it "returns nil for the wrapped sub-entities when absent" do
    bare = ::HermesAgent::Client::Entities::Job.new({})
    assert_nil(bare.schedule)
    assert_nil(bare.repeat)
  end

  it "exposes the raw payload via to_h and []" do
    assert_equal(job_hash, job.to_h)
    assert_equal("0ec925dc7192", job["id"])
  end
end

describe ::HermesAgent::Client::Resources::Jobs do
  # A server response wrapping a single job under "job".
  let(:job_envelope) do
    {"job" => {"id" => "0ec925dc7192", "name" => "Hello world", "state" => "scheduled"}}
  end
  let(:transport) { ::HermesAgent::Tests::FakeTransport.new(job_envelope) }
  def jobs(with = transport)
    ::HermesAgent::Client::Resources::Jobs.new(with)
  end

  describe "#list" do
    let(:list_transport) do
      ::HermesAgent::Tests::FakeTransport.new(
        "jobs" => [{"id" => "0ec925dc7192", "name" => "A"}, {"id" => "1fa836ed8203", "name" => "B"}]
      )
    end

    it "gets the /api/jobs path" do
      jobs(list_transport).list
      assert_equal("/api/jobs", list_transport.requested_path)
    end

    it "returns an array of Job entities unwrapped from the jobs envelope" do
      result = jobs(list_transport).list
      assert_instance_of(::Array, result)
      assert_equal(2, result.size)
      assert(result.all? { |job| job.is_a?(::HermesAgent::Client::Entities::Job) })
      assert_equal(["0ec925dc7192", "1fa836ed8203"], result.map(&:id))
    end

    it "returns an empty array when there are no jobs" do
      empty = ::HermesAgent::Tests::FakeTransport.new("jobs" => [])
      assert_equal([], jobs(empty).list)
    end
  end

  describe "#create" do
    it "posts to the /api/jobs path" do
      jobs.create(name: "probe", schedule: "every 2h")
      assert_equal("/api/jobs", transport.requested_path)
    end

    it "sends the required name and schedule" do
      jobs.create(name: "probe", schedule: "every 2h")
      assert_equal("probe", transport.requested_body[:name])
      assert_equal("every 2h", transport.requested_body[:schedule])
    end

    it "omits the optional fields when not given" do
      jobs.create(name: "probe", schedule: "every 2h")
      [:prompt, :repeat, :deliver, :skills, :script, :no_agent].each do |key|
        refute(transport.requested_body.key?(key), "expected #{key} to be omitted")
      end
    end

    it "sends the optional fields when given" do
      jobs.create(name: "probe", schedule: "every 2h", prompt: "do a thing", repeat: 2,
                  deliver: "local", skills: ["search"], script: "watch.sh", no_agent: true)
      body = transport.requested_body
      assert_equal("do a thing", body[:prompt])
      assert_equal(2, body[:repeat])
      assert_equal("local", body[:deliver])
      assert_equal(["search"], body[:skills])
      assert_equal("watch.sh", body[:script])
      assert_equal(true, body[:no_agent])
    end

    it "sends a false no_agent (not omitted)" do
      jobs.create(name: "probe", schedule: "every 2h", no_agent: false)
      assert_equal(false, transport.requested_body[:no_agent])
    end

    it "does not send the read-only override fields" do
      jobs.create(name: "probe", schedule: "every 2h")
      [:model, :provider, :base_url, :workdir, :profile, :context_from].each do |key|
        refute(transport.requested_body.key?(key), "expected #{key} not to be sent")
      end
    end

    it "merges extra keyword arguments into the body" do
      jobs.create(name: "probe", schedule: "every 2h", skill: "search")
      assert_equal("search", transport.requested_body[:skill])
    end

    it "wraps the created job in a Job entity unwrapped from the job envelope" do
      job = jobs.create(name: "Hello world", schedule: "every 2h")
      assert_instance_of(::HermesAgent::Client::Entities::Job, job)
      assert_equal("0ec925dc7192", job.id)
    end
  end

  describe "#get" do
    it "gets the /api/jobs/{id} path and wraps the job" do
      job = jobs.get("0ec925dc7192")
      assert_equal("/api/jobs/0ec925dc7192", transport.requested_path)
      assert_instance_of(::HermesAgent::Client::Entities::Job, job)
      assert_equal("0ec925dc7192", job.id)
    end
  end

  describe "#update" do
    it "patches the /api/jobs/{id} path" do
      jobs.update("0ec925dc7192", name: "renamed")
      assert_equal("/api/jobs/0ec925dc7192", transport.requested_path)
    end

    it "sends only the given fields" do
      jobs.update("0ec925dc7192", name: "renamed", schedule: "every 1h")
      assert_equal("renamed", transport.requested_body[:name])
      assert_equal("every 1h", transport.requested_body[:schedule])
      refute(transport.requested_body.key?(:prompt))
    end

    it "does not send the read-only override fields" do
      jobs.update("0ec925dc7192", name: "renamed")
      [:model, :provider, :base_url, :workdir, :profile, :context_from].each do |key|
        refute(transport.requested_body.key?(key), "expected #{key} not to be sent")
      end
    end

    it "merges extra keyword arguments into the body" do
      jobs.update("0ec925dc7192", skill: "search")
      assert_equal("search", transport.requested_body[:skill])
    end

    it "wraps the updated job in a Job entity" do
      job = jobs.update("0ec925dc7192", name: "renamed")
      assert_instance_of(::HermesAgent::Client::Entities::Job, job)
    end
  end

  describe "#delete" do
    it "deletes the /api/jobs/{id} path and returns true" do
      deleter = ::HermesAgent::Tests::FakeTransport.new("ok" => true)
      assert_equal(true, jobs(deleter).delete("0ec925dc7192"))
      assert_equal("/api/jobs/0ec925dc7192", deleter.requested_path)
    end
  end

  describe "#pause" do
    it "posts a body-less request to the /api/jobs/{id}/pause path and wraps the job" do
      job = jobs.pause("0ec925dc7192")
      assert_equal("/api/jobs/0ec925dc7192/pause", transport.requested_path)
      assert_equal({}, transport.requested_body)
      assert_instance_of(::HermesAgent::Client::Entities::Job, job)
    end
  end

  describe "#resume" do
    it "posts a body-less request to the /api/jobs/{id}/resume path and wraps the job" do
      job = jobs.resume("0ec925dc7192")
      assert_equal("/api/jobs/0ec925dc7192/resume", transport.requested_path)
      assert_equal({}, transport.requested_body)
      assert_instance_of(::HermesAgent::Client::Entities::Job, job)
    end
  end

  describe "#trigger" do
    it "posts a body-less request to the /api/jobs/{id}/run path and wraps the job" do
      job = jobs.trigger("0ec925dc7192")
      assert_equal("/api/jobs/0ec925dc7192/run", transport.requested_path)
      assert_equal({}, transport.requested_body)
      assert_instance_of(::HermesAgent::Client::Entities::Job, job)
    end
  end
end

describe "jobs" do
  it "is reachable from the client" do
    client = ::HermesAgent::Client.new(base_url: "http://127.0.0.1:8642")
    assert_instance_of(::HermesAgent::Client::Resources::Jobs, client.jobs)
  end

  integration_port = ENV["HERMES_CLIENT_INTEGRATION_PORT"]

  if integration_port
    let(:client) do
      ::HermesAgent::Client.new(base_url: "http://localhost:#{integration_port}",
                                api_key: ::HermesAgent::Tests.integration_api_key)
    end

    # Walk a job through its whole CRUD lifecycle without it ever firing: the
    # schedule is comfortably far out ("every 12h"), so the scheduler never
    # executes it (no LLM call, no cost), and the job is deleted in an ensure so
    # nothing is left behind on the gateway.
    it "creates, reads, updates, pauses, resumes, lists, and deletes a job" do
      created = client.jobs.create(name: "hermes-client probe", schedule: "every 12h",
                                   prompt: "Say hello.", repeat: 1)
      begin
        assert_instance_of(::HermesAgent::Client::Entities::Job, created)
        refute_nil(created.id)
        assert_equal("hermes-client probe", created.name)
        assert_equal(true, created.enabled?)
        assert_equal("scheduled", created.state)
        assert(created.schedule.interval?)
        assert_equal(720, created.schedule.minutes)
        assert_equal(0, created.repeat.completed)
        # The override slots are read-only via this API: ignored on create.
        assert_nil(created.model)

        fetched = client.jobs.get(created.id)
        assert_equal(created.id, fetched.id)
        assert_equal("hermes-client probe", fetched.name)

        assert_includes(client.jobs.list.map(&:id), created.id)

        # PATCH re-parses the schedule (interval -> cron) and recomputes the run.
        updated = client.jobs.update(created.id, name: "renamed probe", schedule: "0 9 * * *")
        assert_equal("renamed probe", updated.name)
        assert(updated.schedule.cron?)
        assert_equal("0 9 * * *", updated.schedule.expr)

        paused = client.jobs.pause(created.id)
        assert_equal("paused", paused.state)
        assert_equal(false, paused.enabled?)
        refute_nil(paused.paused_at)

        resumed = client.jobs.resume(created.id)
        assert_equal("scheduled", resumed.state)
        assert_equal(true, resumed.enabled?)
        assert_nil(resumed.paused_at)
      ensure
        client.jobs.delete(created.id)
      end

      # Once deleted, the job is gone.
      assert_raises(::HermesAgent::Client::NotFoundError) { client.jobs.get(created.id) }
    end

    # Confirms the /run (trigger) path against the live server. Trigger is
    # asynchronous — it advances next_run_at to "now" for the scheduler's next
    # tick and returns immediately. We delete right after, which cancels any
    # in-flight run, so the trivial "Say hello." prompt is very unlikely to
    # actually execute (the scheduler tick lags ~20s); worst-case cost is one
    # tiny run.
    it "triggers a job out of schedule against the live gateway" do
      created = client.jobs.create(name: "hermes-client trigger probe", schedule: "every 12h",
                                   prompt: "Say hello.", repeat: 1)
      begin
        triggered = client.jobs.trigger(created.id)
        assert_instance_of(::HermesAgent::Client::Entities::Job, triggered)
        assert_equal(created.id, triggered.id)
      ensure
        client.jobs.delete(created.id)
      end
    end

    it "raises NotFoundError for a well-formed but unknown job id" do
      assert_raises(::HermesAgent::Client::NotFoundError) do
        client.jobs.get("f" * 12)
      end
    end

    it "raises BadRequestError for a malformed job id" do
      assert_raises(::HermesAgent::Client::BadRequestError) do
        client.jobs.get("nonexistent123")
      end
    end

    it "raises BadRequestError when name is missing" do
      assert_raises(::HermesAgent::Client::BadRequestError) do
        client.jobs.create(name: "", schedule: "every 12h")
      end
    end

    # A bad schedule is rejected as a 500 (ServerError), not a 400, even though
    # it is really invalid user input — see the resource's create YARD.
    it "raises ServerError for an unparseable schedule" do
      assert_raises(::HermesAgent::Client::ServerError) do
        client.jobs.create(name: "hermes-client bad-schedule", schedule: "not a real schedule")
      end
    end
  end
end
