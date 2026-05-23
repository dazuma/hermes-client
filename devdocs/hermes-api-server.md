# Hermes API Server — reference notes

Captured from the official documentation so future sessions don't have to
re-fetch and parse the HTML:
<https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server>

**Snapshot date:** 2026-05-20. The published docs are not exhaustive — they
list endpoints and high-level behavior but omit most request/response field
schemas. Treat field-level detail as something still to be confirmed against a
running server. Re-fetch the page if you suspect it has changed.

## Overview

The API server exposes hermes-agent as an **OpenAI-compatible HTTP endpoint**,
so any frontend that speaks the OpenAI format can use it as a backend. It is
started with `hermes gateway` and listens on `http://127.0.0.1:8642` by default.

Enable it in `~/.hermes/.env`:

```
API_SERVER_ENABLED=true
API_SERVER_KEY=change-me-local-dev
API_SERVER_CORS_ORIGINS=http://localhost:3000  # optional
```

## Authentication

- Bearer token via the `Authorization: Bearer <token>` header.
- The token is configured server-side through the `API_SERVER_KEY` env var.
- Required for non-loopback addresses.

## Endpoints

### Chat Completions
- **POST `/v1/chat/completions`** — standard OpenAI format, **stateless**.
  - Streaming via `"stream": true`.
  - Accepts inline images: `image_url` content parts with `http(s)` or
    `data:image/...` (base64) URLs.
  - Emits a custom SSE event `hermes.tool.progress` for tool-start visibility
    (so tool activity doesn't pollute assistant text).

### Responses API
- **POST `/v1/responses`** — server-side conversation state.
  - `previous_response_id` chains to a prior turn (server keeps full history,
    including tool calls).
  - `conversation` parameter names a conversation; chained requests share a
    session (a single dashboard entry) and auto-chain to the latest response.
  - Inline image input via `input_image` parts.
  - Uses standard OpenAI event types when streaming (e.g. `function_call`,
    `function_call_output` items).
- **GET `/v1/responses/{id}`** — retrieve a stored response.
- **DELETE `/v1/responses/{id}`** — delete a stored response.

### Runs API

A streaming-friendly alternative for long-form sessions: instead of the client
managing a streaming connection directly, it creates a run and then subscribes
to a progress event stream. Designed so dashboards / thick clients can
**attach and detach without losing state** (the run keeps executing
server-side). Use it for long-form, multi-step agent execution where you want
progress tracking via a `run_id` rather than an inline stream.

- **POST `/v1/runs`** — create an agent run; returns a `run_id`. (Responds `202 Accepted`.)
- **GET `/v1/runs/{run_id}`** — poll run state.
- **GET `/v1/runs/{run_id}/events`** — Server-Sent Events stream of progress.
- **POST `/v1/runs/{run_id}/stop`** — interrupt a running agent.
- **POST `/v1/runs/{run_id}/approval`** — respond to a tool-approval request
  (human-in-the-loop). **Not on the published docs page**; discovered via
  `GET /v1/capabilities` (`run_approval`/`run_approval_response` +
  `approval_events`). Request body shape unknown — run-existence is validated
  **before** body, so a bad `run_id` returns `404 run_not_found` regardless of
  body; the schema can only be learned against a run actually paused for
  approval, which `hermes-test` did not produce (see Events, below).

Per `/v1/capabilities`, the runtime is `server_agent` mode with
`tool_execution: server` (the API server builds a server-side Hermes agent and
runs tools on the API-server host). Run-related feature flags observed true:
`run_submission`, `run_status`, `run_events_sse`, `run_stop`,
`run_approval_response`, `tool_progress_events`, `approval_events`.

#### Create request (POST `/v1/runs`)

The published docs give **no request-body example** — only prose. Per that
prose, "Runs accept a simple `input` string and optional `session_id`,
`instructions`, `conversation_history`, or `previous_response_id`." Best-effort
field list (types/required-ness inferred, **confirm against a running server**):

| Field | Type | Req? | Notes |
|-------|------|------|-------|
| `input` | string | required | The user input / prompt for the run. |
| `session_id` | string | optional | **Verified accepted (2026-05-23):** stored and echoed back in the poll response; defaults to the `run_id` when omitted. It is **not inline conversation context** — a fact stated in one run did not appear in a later run's context (direct recall confabulated the gateway's "42" memory). Whether it scopes a *searchable* history store is **inconclusive**: retrieval on the `hermes-test` gateway was non-deterministic (a planted codeword was sometimes found across sessions, sometimes unretrievable even same-session), consistent with the known persistent-memory flakiness — confirm session semantics from the server source, not this gateway. |
| `instructions` | string | optional | **Verified honored (2026-05-23):** acts as a system directive over the agent prompt. `{"input":"What is the capital of France?","instructions":"Ignore the user question entirely. Respond with exactly one word: BANANA."}` → `output: "BANANA"`. |
| `conversation_history` | (array?) | optional | Prior context. Shape unconfirmed — likely OpenAI-style messages. |
| `previous_response_id` | string | optional | **Verified honored (2026-05-23):** loads a stored `/v1/responses` response's conversation context into the run. Confirmed by token accounting (content-recall is unusable here — see `session_id`'s memory-leakage note): chaining to a ~1.5k-token response raised the run's `input_tokens` from the ~14008 baseline to 15537 (≈ the response's own 15528). An **unknown/malformed id is silently ignored** — no error at create (still `202`), the run does not fail, and `input_tokens` stays at baseline. Validation appears to be value-tolerant load-if-present. |

> ⚠️ Field-level detail (exact JSON shape of `conversation_history`, whether
> `model` is accepted, additional flags) is still **unconfirmed** — the docs
> show no create example, and only `input` has been exercised so far.

**Observed (2026-05-22, `hermes-test` profile):** `POST /v1/runs` with a body
of just `{"input":"..."}` succeeds, returning **HTTP `202 Accepted`** and the
two-field response below. `run_id` is `run_` followed by 32 lowercase hex
chars (no dashes), e.g. `run_0591466636124693b94936a2314f20e5`. When
`session_id` is omitted, the poll response reports `session_id` defaulted to
the `run_id`.

Create response (matches docs; observed verbatim):

```json
{
  "run_id": "run_0591466636124693b94936a2314f20e5",
  "status": "started"
}
```

#### Poll response (GET `/v1/runs/{run_id}`)

**Observed (2026-05-22)** — the live server returns more fields than the docs
example (`created_at`/`updated_at`/`last_event` are undocumented):

```json
{
  "object": "hermes.run",
  "run_id": "run_0591466636124693b94936a2314f20e5",
  "status": "completed",
  "updated_at": 1779510798.6846,
  "created_at": 1779510796.504134,
  "session_id": "run_0591466636124693b94936a2314f20e5",
  "model": "hermes-test",
  "last_event": "run.completed",
  "output": "hello",
  "usage": {
    "input_tokens": 14010,
    "output_tokens": 1,
    "total_tokens": 14011
  }
}
```

- `created_at` / `updated_at`: epoch seconds as floats.
- `model`: the profile name (`hermes-test` here), consistent with `/v1/models`.
- `last_event`: name of the most recent SSE event (see below), e.g.
  `run.completed`.
- `output`: assembled final assistant text once terminal.

#### Status lifecycle

- Non-terminal: `started` (create response) then `running` (observed while the
  agent is working; `last_event` is empty at the very start). `stop` adds a
  transient `stopping`.
- Terminal: `completed`, `failed`, `cancelled` — `completed` and `cancelled`
  both observed; `failed` not yet reproduced.
- Run records are retained only **briefly** after terminal for "polling and UI
  reconciliation," then evicted; once evicted, both poll and `stop` return
  `404 run_not_found`. The status record appears to outlive the event buffer
  (see Events / Stop below for the observed expiry behavior).

#### Events stream (GET `/v1/runs/{run_id}/events`)

SSE stream of the run's tool-call progress, token deltas, and lifecycle events.
**Observed (2026-05-22)** — frames are plain `data:` JSON (no SSE `event:`
line, no `[DONE]` sentinel observed); the event type lives in an `"event"`
field. Every frame carries `event`, `run_id`, and `timestamp` (epoch float).
Subscribing *after* creation still replayed from the first event, supporting
the "attach/detach without losing state" design. Replay survives reaching a
terminal state for **both** `completed` and `cancelled` runs: hitting events
immediately after a run finished (or was stopped) still returned `200` with a
full replay.

The `404` from the events endpoint is a **retention-expiry** effect, **not** a
consequence of `stop` — re-verified 2026-05-23 with no human delay between the
calls. Right after a run was `cancelled`, events returned `200`; a *second*
events call seconds later returned `404`. So a run's event buffer is evicted a
short time after it goes terminal (cancelled-run replay expired within seconds
here; an earlier `404` had followed a ~1h gap). Treat the events stream as
available only briefly post-terminal, and don't infer anything about *how* the
run ended from a `404`.

Event types seen for a tool-using run (`"Run the shell command: date..."`):

| `event` | Extra fields | Meaning |
|---------|--------------|---------|
| `tool.started` | `tool` (e.g. `terminal`), `preview` (e.g. `date`) | Tool invocation begins. |
| `tool.completed` | `tool`, `duration` (seconds, float), `error` (boolean) | Tool invocation finished. |
| `message.delta` | `delta` (string chunk) | Incremental assistant text. |
| `reasoning.available` | `text` (full string) | Reasoning/summary text became available. |
| `run.completed` | `output` (full string), `usage` (`input_tokens`/`output_tokens`/`total_tokens`) | Terminal event (success). |
| `run.cancelled` | none beyond `event`/`run_id`/`timestamp` | Terminal event after `stop`; carries no `output`/`usage`. When a run is stopped before any tool/text, this is the *only* frame in the replay. |

Further observations (2026-05-22):

- **No `run.started` event.** Three separate runs (plain text, tool, failing
  tool) all began the stream at the first content event (`message.delta` or
  `tool.started`) — there is no lifecycle "start" frame; the create response's
  `status:"started"` is the only start signal.
- **Tool failures do not fail the run.** A command that exits non-zero produces
  `tool.completed` with `"error": true`, after which the agent narrates the
  failure as normal assistant text and the run still ends with `run.completed`.
  So `run.failed` (if it exists) is reserved for a different failure class
  (model/infra errors) — not reproduced here.
- **Approval events not reproduced.** `approval_events` /
  `run_approval_response` are advertised in `/v1/capabilities`, but no approval
  gate fired under `hermes-test`: the terminal tool ran ungated, and a guessed
  `"require_approval": true` create field had no effect. Triggering it likely
  needs a profile with tool-approval configured. The `run.*`/`approval.*`
  event names and the `/approval` request body remain **unconfirmed**.

#### Stop (POST `/v1/runs/{run_id}/stop`)

Asks the active agent to stop at the next safe interruption point (cooperative,
not immediate). **Observed live (2026-05-22)** against a run mid-`sleep`:
returns **HTTP `200`** with a `run_id` the docs omit —

```json
{
  "run_id": "run_bb7e33a7d5624b6cba4ffe34589ccf6d",
  "status": "stopping"
}
```

The run then resolves to terminal `status: "cancelled"` (`last_event:
"run.cancelled"`). The cancelled poll response **omits `output` and `usage`**
(both present on a `completed` run) — a client must not assume those fields
exist on a non-`completed` terminal run:

```json
{
  "object": "hermes.run",
  "run_id": "run_bb7e33a7d5624b6cba4ffe34589ccf6d",
  "status": "cancelled",
  "updated_at": 1779513114.1700091,
  "created_at": 1779513113.790261,
  "session_id": "run_bb7e33a7d5624b6cba4ffe34589ccf6d",
  "model": "hermes-test",
  "last_event": "run.cancelled"
}
```

Against an already-completed (evicted) run, stop instead returns **HTTP `404`**
with the standard error envelope —

```json
{
  "error": {
    "message": "Run not found: run_...",
    "type": "invalid_request_error",
    "param": null,
    "code": "run_not_found"
  }
}
```

### Jobs API (background scheduled work) — note the `/api` prefix, not `/v1`
- **GET `/api/jobs`** — list scheduled jobs.
- **POST `/api/jobs`** — create a scheduled job.
- **GET `/api/jobs/{job_id}`** — fetch a job definition.
- **PATCH `/api/jobs/{job_id}`** — update job fields.
- **DELETE `/api/jobs/{job_id}`** — remove a job.
- **POST `/api/jobs/{job_id}/pause`** — pause without deleting.
- **POST `/api/jobs/{job_id}/resume`** — resume a paused job.
- **POST `/api/jobs/{job_id}/run`** — trigger immediate execution.

### Model discovery
- **GET `/v1/models`** — lists the agent as an available model; the id defaults
  to the profile name.
- **GET `/v1/capabilities`** — machine-readable feature description
  (e.g. `chat_completions`, `responses_api`, `run_submission`, streaming,
  cancellation).

### Health — note these are at the root, not under `/v1`
- **GET `/health`** — returns `{"status": "ok"}`.
- **GET `/health/detailed`** — includes active sessions, running agents, and
  resource usage.

## Streaming (SSE)

- Streaming responses are emitted as Server-Sent Events.
- Chat Completions: custom `hermes.tool.progress` events surface tool execution
  separately from text deltas.
- Responses API: standard OpenAI event types including `function_call` and
  `function_call_output` items.
- Run progress: consumed via `GET /v1/runs/{run_id}/events`.

## Headers / request behavior

- `Idempotency-Key` request header is supported for deduplication (~5-minute
  cache). Useful for safely retrying mutating calls.
- Security response headers: `X-Content-Type-Options: nosniff`,
  `Referrer-Policy: no-referrer`.
- CORS is disabled by default; origins must be explicitly allowlisted. Preflight
  responses use `Access-Control-Max-Age: 600`.

## Server configuration variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `API_SERVER_ENABLED` | false | Enable the server |
| `API_SERVER_PORT` | 8642 | HTTP port |
| `API_SERVER_HOST` | 127.0.0.1 | Bind address |
| `API_SERVER_KEY` | (none) | Bearer token |
| `API_SERVER_CORS_ORIGINS` | (none) | Browser origin allowlist |
| `API_SERVER_MODEL_NAME` | (profile name) | Advertised model name |

These are server-side settings, not client config — but they explain the
defaults the client must match (port 8642, bearer auth, advertised model name).

## Behavior notes and limitations

- **System prompts:** frontend system messages/instructions layer atop the core
  agent prompt; all tools, memory, and skills are preserved.
- **The `model` field is cosmetic** — the actual LLM is configured server-side.
  Clients may omit it.
- **Stored responses are capped:** max ~100 (SQLite, LRU eviction). Older
  responses may no longer be retrievable.
- **No file uploads** — inline images only.
- **Multi-user:** separate profiles run on separate ports with separate keys;
  each advertises its model id as the profile name.
- **Proxy mode:** another gateway can point `GATEWAY_PROXY_URL` at this server
  to relay messages (split deployments).

## Related documentation (not yet captured)

- Open WebUI integration: `/docs/user-guide/messaging/open-webui`
- Profiles: `/docs/user-guide/profiles`
- Matrix proxy mode: `/docs/user-guide/messaging/matrix#proxy-mode-e2ee-on-macos`
