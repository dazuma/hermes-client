# frozen_string_literal: true

require "hermes_agent/client/entities/job"

module HermesAgent
  class Client
    module Resources
      ##
      # The jobs resource: the Jobs API (`/api/jobs`) for scheduled background
      # work — cron-like recurring tasks, one-shot deferred tasks, and watchdog
      # scripts. On a server configured with an API key, these calls require a
      # bearer token (see {Client} / {Configuration}).
      #
      # Note this resource lives under `/api/jobs`, **not** `/v1`, and is **not**
      # advertised in `/v1/capabilities` — it may be gated, versioned
      # separately, or absent in some builds; confirm against a server that
      # exposes it.
      #
      # **No terminal state to poll.** The server **deletes** a job once it is
      # exhausted: a one-shot (`once`) job is gone after its single run, and a
      # `repeat`-capped job is gone after its final run. After that, {#get} (and
      # {#trigger}) raise {NotFoundError} — a client cannot poll such a job for
      # its outcome once it completes.
      #
      class Jobs
        ##
        # Create the resource.
        #
        # @param transport [Transport] The transport used to issue requests.
        #
        def initialize(transport)
          @transport = transport
        end

        ##
        # List the scheduled jobs.
        #
        # @return [Array<Entities::Job>] The jobs (empty when there are none).
        # @raise [APIError] If the server returns a non-2xx response.
        #
        def list
          body = @transport.get("/api/jobs")
          Array(body["jobs"]).map { |raw| Entities::Job.new(raw) }
        end

        ##
        # Create a scheduled job. `name` and `schedule` are required.
        #
        # `schedule` is a string parsed server-side into a `once` / `interval` /
        # `cron` schedule: a bare duration (`"30m"`), an absolute timestamp
        # (`"2027-02-03T14:00:00"`), an interval (`"every 30m"`), or a cron
        # expression (`"0 9 * * *"`). The override slots (`model`, `provider`,
        # `base_url`, `workdir`, `profile`, `context_from`) are **not** writable
        # via this API and so are not parameters — they are silently ignored if
        # sent. A caller who really wants to send unmodeled fields can pass them
        # through `extra`.
        #
        # @param name [String] The job name (required).
        # @param schedule [String] The schedule string (required; see above).
        # @param prompt [String, nil] The task instruction. Omitted when `nil`.
        # @param repeat [Integer, nil] The maximum number of runs (`nil` =
        #     unbounded). Omitted when `nil`.
        # @param deliver [String, nil] The delivery target (defaults server-side
        #     to `"local"`). Omitted when `nil`. Not validated on write.
        # @param skills [Array<String>, nil] Attached skill names. Omitted when
        #     `nil`.
        # @param script [String, nil] A script path under `~/.hermes/scripts/`.
        #     Omitted when `nil`.
        # @param no_agent [Boolean, nil] Whether to skip the LLM and deliver the
        #     script's stdout verbatim. Omitted when `nil` (so `false` is sent).
        # @param extra [Hash] Additional request-body fields merged in as-is.
        # @return [Entities::Job] The created job.
        # @raise [BadRequestError] On a missing `name`/`schedule` (`400`).
        # @raise [ServerError] On an **unparseable `schedule`** — the server
        #     returns `500`, not `400`, even though it is really invalid input.
        # @raise [APIError] If the server returns another non-2xx response.
        #
        def create(name:, schedule:, prompt: nil, repeat: nil, deliver: nil,
                   skills: nil, script: nil, no_agent: nil, **extra)
          body = {name: name, schedule: schedule, **extra}
          body[:prompt] = prompt unless prompt.nil?
          body[:repeat] = repeat unless repeat.nil?
          body[:deliver] = deliver unless deliver.nil?
          body[:skills] = skills unless skills.nil?
          body[:script] = script unless script.nil?
          body[:no_agent] = no_agent unless no_agent.nil?
          Entities::Job.new(@transport.post("/api/jobs", body).body["job"])
        end

        ##
        # Retrieve a job by id.
        #
        # @param job_id [String] The job id (12 hex characters).
        # @return [Entities::Job] The current job state.
        # @raise [NotFoundError] If no such job exists — including a job the
        #     server already deleted because it was exhausted (a `once` job after
        #     its run, or a capped job after its final run).
        # @raise [APIError] If the server returns another non-2xx response.
        #
        def get(job_id)
          Entities::Job.new(@transport.get("/api/jobs/#{job_id}")["job"])
        end

        ##
        # Update a job (a partial merge over the writable fields). Sent fields
        # are merged onto the existing job; a sent `schedule` is re-parsed and
        # `next_run_at` recomputed. The override slots are **not** writable here
        # either (silently ignored), so they are not parameters.
        #
        # @param job_id [String] The job id (12 hex characters).
        # @param name [String, nil] A new name. Omitted when `nil`.
        # @param schedule [String, nil] A new schedule string (re-parsed).
        #     Omitted when `nil`.
        # @param prompt [String, nil] A new prompt. Omitted when `nil`.
        # @param repeat [Integer, nil] A new run cap. Omitted when `nil`.
        # @param deliver [String, nil] A new delivery target. Omitted when `nil`.
        # @param skills [Array<String>, nil] New skill names. Omitted when `nil`.
        # @param script [String, nil] A new script path. Omitted when `nil`.
        # @param no_agent [Boolean, nil] A new `no_agent` flag. Omitted when
        #     `nil`.
        # @param extra [Hash] Additional request-body fields merged in as-is.
        # @return [Entities::Job] The updated job.
        # @raise [NotFoundError] If no such job exists.
        # @raise [ServerError] On an **unparseable `schedule`** (`500`, not
        #     `400`; see {#create}).
        # @raise [APIError] If the server returns another non-2xx response.
        #
        def update(job_id, name: nil, schedule: nil, prompt: nil, repeat: nil,
                   deliver: nil, skills: nil, script: nil, no_agent: nil, **extra)
          body = {**extra}
          body[:name] = name unless name.nil?
          body[:schedule] = schedule unless schedule.nil?
          body[:prompt] = prompt unless prompt.nil?
          body[:repeat] = repeat unless repeat.nil?
          body[:deliver] = deliver unless deliver.nil?
          body[:skills] = skills unless skills.nil?
          body[:script] = script unless script.nil?
          body[:no_agent] = no_agent unless no_agent.nil?
          Entities::Job.new(@transport.patch("/api/jobs/#{job_id}", body)["job"])
        end

        ##
        # Delete a job (also cancels any in-flight run).
        #
        # @param job_id [String] The job id (12 hex characters).
        # @return [Boolean] `true` (mapped from the server's `{"ok": true}`).
        # @raise [NotFoundError] If no such job exists.
        # @raise [APIError] If the server returns another non-2xx response.
        #
        def delete(job_id)
          @transport.delete("/api/jobs/#{job_id}")["ok"] == true
        end

        ##
        # Pause a job without deleting it (sets `enabled: false`). Idempotent:
        # pausing an already-paused job is not an error.
        #
        # @param job_id [String] The job id (12 hex characters).
        # @return [Entities::Job] The paused job.
        # @raise [NotFoundError] If no such job exists.
        # @raise [APIError] If the server returns another non-2xx response.
        #
        def pause(job_id)
          Entities::Job.new(@transport.post("/api/jobs/#{job_id}/pause", {}).body["job"])
        end

        ##
        # Resume a paused job (recomputes `next_run_at` from the resume time).
        # Idempotent: resuming an already-scheduled job is not an error.
        #
        # @param job_id [String] The job id (12 hex characters).
        # @return [Entities::Job] The resumed job.
        # @raise [NotFoundError] If no such job exists.
        # @raise [APIError] If the server returns another non-2xx response.
        #
        def resume(job_id)
          Entities::Job.new(@transport.post("/api/jobs/#{job_id}/resume", {}).body["job"])
        end

        ##
        # Trigger a job to run out of schedule.
        #
        # This is **asynchronous**: it advances the job's `next_run_at` to "now"
        # so the scheduler picks it up on its next tick, then returns the job
        # immediately — it does **not** block on or return the run's result, and
        # `last_run_at` / `last_status` / `repeat.completed` are not yet updated
        # when it returns. (For a one-shot or final-run job, the job may be
        # deleted once it fires, so it cannot be polled afterward — see {#get}.)
        #
        # @param job_id [String] The job id (12 hex characters).
        # @return [Entities::Job] The job, with `next_run_at` advanced.
        # @raise [NotFoundError] If no such job exists.
        # @raise [APIError] If the server returns another non-2xx response.
        #
        def trigger(job_id)
          Entities::Job.new(@transport.post("/api/jobs/#{job_id}/run", {}).body["job"])
        end
      end
    end
  end
end
