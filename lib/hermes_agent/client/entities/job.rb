# frozen_string_literal: true

require "hermes_agent/client/entity"

module HermesAgent
  class Client
    module Entities
      ##
      # The repeat policy of a {Job} ({Job#repeat}): how many times the job runs
      # before the server deletes it, and how many runs it has completed so far.
      #
      class JobRepeat < Entity
        ##
        # The maximum number of runs, or `nil` for an unbounded (uncapped)
        # recurring job. Once a capped job reaches this many runs the server
        # deletes it.
        # @return [Integer, nil]
        #
        def times
          self["times"]
        end

        ##
        # The number of runs completed so far (incremented per executed run).
        # @return [Integer, nil]
        #
        def completed
          self["completed"]
        end
      end

      ##
      # The schedule of a {Job} ({Job#schedule}): a tagged union discriminated by
      # {#kind}. The create/update `schedule` string is parsed server-side into
      # one of three kinds, each carrying its own payload:
      #
      # - `"once"` — a one-shot run at {#run_at} (an ISO-8601 string).
      # - `"interval"` — a recurring run every {#minutes} minutes.
      # - `"cron"` — a recurring run on the cron expression {#expr}.
      #
      # Use the {#once?} / {#interval?} / {#cron?} predicates to discriminate.
      # The payload readers ({#run_at} / {#minutes} / {#expr}) return `nil` when
      # the schedule is not of their kind. {#display} is a human-readable form of
      # the schedule for any kind. Field readers are best-effort; {#to_h} remains
      # the source of truth.
      #
      class JobSchedule < Entity
        ##
        # The schedule kind: `"once"`, `"interval"`, or `"cron"`.
        # @return [String, nil]
        #
        def kind
          self["kind"]
        end

        ##
        # Whether this is a one-shot (`"once"`) schedule.
        # @return [boolean]
        #
        def once?
          kind == "once"
        end

        ##
        # Whether this is a recurring interval (`"interval"`) schedule.
        # @return [boolean]
        #
        def interval?
          kind == "interval"
        end

        ##
        # Whether this is a recurring cron (`"cron"`) schedule.
        # @return [boolean]
        #
        def cron?
          kind == "cron"
        end

        ##
        # A human-readable rendering of the schedule (e.g. `"every 120m"`,
        # `"0 9 * * *"`, or `"once at 2027-02-03 14:00"`).
        # @return [String, nil]
        #
        def display
          self["display"]
        end

        ##
        # The scheduled run time of a `"once"` schedule, as an ISO-8601 string.
        # Returns `nil` when the schedule is not of kind `"once"`.
        # @return [String, nil]
        #
        def run_at
          self["run_at"]
        end

        ##
        # The interval in minutes of an `"interval"` schedule. Returns `nil` when
        # the schedule is not of kind `"interval"`.
        # @return [Integer, nil]
        #
        def minutes
          self["minutes"]
        end

        ##
        # The cron expression of a `"cron"` schedule. Returns `nil` when the
        # schedule is not of kind `"cron"`.
        # @return [String, nil]
        #
        def expr
          self["expr"]
        end
      end

      ##
      # A scheduled background job from the Jobs API (`/api/jobs`): a cron-like
      # recurring task, a one-shot deferred task, or a watchdog script. The same
      # object is returned by create, get, list, update, pause, resume, and
      # trigger.
      #
      # Note the timestamp fields ({#created_at} / {#next_run_at} /
      # {#last_run_at} / {#paused_at}) are **ISO-8601 strings with an offset**,
      # not the epoch floats the runs and responses APIs use; they are exposed
      # verbatim with no Time parsing. The override slots ({#model} /
      # {#provider} / {#base_url} / {#workdir} / {#profile} / {#context_from}) are
      # **read-only** here — the HTTP API ignores them on create/update, so they
      # are surfaced as readers but are not create/update parameters.
      #
      # Field readers are best-effort; {#to_h} remains the source of truth.
      #
      class Job < Entity
        ##
        # The job id: 12 lowercase hex characters (no `run_`-style prefix).
        # @return [String, nil]
        #
        def id
          self["id"]
        end

        ##
        # The human-friendly job name (required on create).
        # @return [String, nil]
        #
        def name
          self["name"]
        end

        ##
        # The task instruction given to the agent each run. `nil` for a
        # `no_agent` script job, which needs none.
        # @return [String, nil]
        #
        def prompt
          self["prompt"]
        end

        ##
        # The attached skill names. The singular {#skill} is a separate scalar
        # slot.
        # @return [Array<String>, nil]
        #
        def skills
          self["skills"]
        end

        ##
        # The single attached skill (a scalar slot separate from {#skills});
        # `nil` when unused.
        # @return [String, nil]
        #
        def skill
          self["skill"]
        end

        ##
        # The per-job model override. **Read-only via this API** (ignored on
        # create/update); `nil` means the profile's configured model is used.
        # @return [String, nil]
        #
        def model
          self["model"]
        end

        ##
        # The per-job provider override. **Read-only via this API**; `nil` =
        # the profile's configured provider.
        # @return [String, nil]
        #
        def provider
          self["provider"]
        end

        ##
        # The per-job base URL override. **Read-only via this API**; `nil` =
        # the profile's configured base URL.
        # @return [String, nil]
        #
        def base_url
          self["base_url"]
        end

        ##
        # The path of a script (under `~/.hermes/scripts/`) run each execution;
        # by default its stdout is injected into the agent prompt.
        # @return [String, nil]
        #
        def script
          self["script"]
        end

        ##
        # Whether the LLM is skipped entirely: the {#script} runs and its stdout
        # is delivered verbatim (the watchdog pattern).
        # @return [boolean, nil]
        #
        def no_agent?
          self["no_agent"]
        end

        ##
        # The source to pull run context from. **Read-only via this API**.
        # @return [String, nil]
        #
        def context_from
          self["context_from"]
        end

        ##
        # The schedule, wrapped in a {JobSchedule}. Returns `nil` when absent.
        # @return [JobSchedule, nil]
        #
        def schedule
          raw = self["schedule"]
          raw.is_a?(::Hash) ? JobSchedule.new(raw) : nil
        end

        ##
        # A human-readable rendering of the schedule (mirrors
        # {JobSchedule#display}).
        # @return [String, nil]
        #
        def schedule_display
          self["schedule_display"]
        end

        ##
        # The repeat policy, wrapped in a {JobRepeat}. Returns `nil` when absent.
        # @return [JobRepeat, nil]
        #
        def repeat
          raw = self["repeat"]
          raw.is_a?(::Hash) ? JobRepeat.new(raw) : nil
        end

        ##
        # Whether the job is enabled (`false` while paused).
        # @return [boolean, nil]
        #
        def enabled?
          self["enabled"]
        end

        ##
        # The lifecycle state, e.g. `"scheduled"` or `"paused"`. (There is no
        # terminal state — an exhausted one-shot or capped job is deleted by the
        # server.)
        # @return [String, nil]
        #
        def state
          self["state"]
        end

        ##
        # When the job was paused, as an ISO-8601 string; `nil` when not paused.
        # @return [String, nil]
        #
        def paused_at
          self["paused_at"]
        end

        ##
        # The optional reason the job was paused; `nil` for a manual pause.
        # @return [String, nil]
        #
        def paused_reason
          self["paused_reason"]
        end

        ##
        # When the job was created, as an ISO-8601 string with offset.
        # @return [String, nil]
        #
        def created_at
          self["created_at"]
        end

        ##
        # When the job is next scheduled to run, as an ISO-8601 string with
        # offset.
        # @return [String, nil]
        #
        def next_run_at
          self["next_run_at"]
        end

        ##
        # When the job last ran, as an ISO-8601 string with offset; `nil` until
        # the first execution.
        # @return [String, nil]
        #
        def last_run_at
          self["last_run_at"]
        end

        ##
        # The outcome of the most recent run, e.g. `"ok"`; `nil` before the
        # first run.
        # @return [String, nil]
        #
        def last_status
          self["last_status"]
        end

        ##
        # The error detail from the last execution, or `nil` on success.
        # @return [String, nil]
        #
        def last_error
          self["last_error"]
        end

        ##
        # The error detail from the last delivery attempt, or `nil` on success.
        # @return [String, nil]
        #
        def last_delivery_error
          self["last_delivery_error"]
        end

        ##
        # The delivery target, e.g. `"local"`, `"origin"`, `"telegram"`, or
        # `"platform:chat_id"`. Defaults to `"local"`.
        # @return [String, nil]
        #
        def deliver
          self["deliver"]
        end

        ##
        # The originating channel info (for `deliver: "origin"`), passed through
        # raw; `nil` for locally created jobs. Its populated shape was never
        # observed, so it is not wrapped — use {#to_h} / {#[]} if a shape appears.
        # @return [Object, nil]
        #
        def origin
          self["origin"]
        end

        ##
        # The toolset allowlist, passed through raw; `nil` = the default set.
        # Expected to be a plain array of names if populated (never observed), so
        # it is not wrapped.
        # @return [Object, nil]
        #
        def enabled_toolsets
          self["enabled_toolsets"]
        end

        ##
        # The absolute working directory for the run. **Read-only via this API**;
        # `nil` = no project context.
        # @return [String, nil]
        #
        def workdir
          self["workdir"]
        end

        ##
        # The Hermes profile the job runs under. **Read-only via this API**;
        # `nil` = the scheduler's existing profile.
        # @return [String, nil]
        #
        def profile
          self["profile"]
        end
      end
    end
  end
end
