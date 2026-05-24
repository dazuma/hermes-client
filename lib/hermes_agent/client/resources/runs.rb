# frozen_string_literal: true

require "hermes_agent/client/entities/run"

module HermesAgent
  class Client
    module Resources
      ##
      # The runs resource: the Runs API (`/v1/runs`) for long-running agent
      # runs. Unlike chat completions and the Responses API, a run is
      # **server-side asynchronous**: {#create} returns immediately (HTTP `202`)
      # with a minimal {Entities::Run} carrying only its `run_id` and `status`,
      # and progress is tracked by polling {#get} (or, later, by subscribing to
      # the event stream). On a server configured with an API key, these calls
      # require a bearer token (see {Client} / {Configuration}).
      #
      # Run records are retained only briefly after they reach a terminal
      # status, then evicted, so callers should not assume an older run remains
      # retrievable.
      #
      class Runs
        ##
        # Create the resource.
        #
        # @param transport [Transport] The transport used to issue requests.
        #
        def initialize(transport)
          @transport = transport
        end

        ##
        # Start a run.
        #
        # Returns as soon as the run is accepted; the returned {Entities::Run}
        # carries only its `run_id` and an initial `status` of `"started"`. Poll
        # {#get} with that id to follow the run to a terminal status.
        #
        # No `model` is sent: the model is configured server-side. (A caller who
        # really wants to send fields we have not modeled — including `model` —
        # can pass them through `extra`.)
        #
        # @param input [String] The user prompt (required).
        # @param instructions [String, nil] A system directive layered over the
        #     agent prompt. Omitted from the request when `nil`.
        # @param conversation_history [Array<Hash>, nil] Prior turns as an
        #     OpenAI-style message array (`[{role:, content:}, …]`), loaded into
        #     the run's context. Omitted from the request when `nil`.
        # @param previous_response_id [String, nil] The id of a stored
        #     `/v1/responses` response whose context should be loaded into the
        #     run. Omitted from the request when `nil`.
        # @param session_id [String, nil] A correlation label, stored and echoed
        #     back on the poll. Omitted from the request when `nil`.
        # @param extra [Hash] Additional request-body fields merged in as-is.
        # @return [Entities::Run] The accepted run (minimal: `run_id` + status).
        # @raise [APIError] If the server returns a non-2xx response.
        #
        def create(input:, instructions: nil, conversation_history: nil,
                   previous_response_id: nil, session_id: nil, **extra)
          body = {input: input, **extra}
          body[:instructions] = instructions if instructions
          body[:conversation_history] = conversation_history if conversation_history
          body[:previous_response_id] = previous_response_id if previous_response_id
          body[:session_id] = session_id if session_id
          Entities::Run.new(@transport.post("/v1/runs", body).body)
        end

        ##
        # Retrieve a run by id, to poll its progress and status.
        #
        # @param run_id [String] The run id (`"run_…"`).
        # @return [Entities::Run] The current run state.
        # @raise [NotFoundError] If no such run exists (or it was evicted).
        # @raise [APIError] If the server returns another non-2xx response.
        #
        def get(run_id)
          Entities::Run.new(@transport.get("/v1/runs/#{run_id}"))
        end
      end
    end
  end
end
