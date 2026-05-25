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
  `approval_events`). Body is `{"choice": "<once|session|always|deny>"}`; full
  flow documented under **Approval workflow**, below. (Run-existence is
  validated **before** the body, so a bad `run_id` returns `404 run_not_found`
  regardless of body.)

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
| `conversation_history` | array of message objects | optional | **Verified (2026-05-23):** an OpenAI-style messages array (`[{"role":"user","content":"…"},{"role":"assistant","content":"…"}]`) is accepted and **loaded into context** — a ~1.5k-token history raised the run's `input_tokens` from the ~14008 baseline to 15533. **Validated** (unlike `previous_response_id`): a non-array value returns `400` `"'conversation_history' must be an array of message objects"`. |
| `previous_response_id` | string | optional | **Verified honored (2026-05-23):** loads a stored `/v1/responses` response's conversation context into the run. Confirmed by token accounting (content-recall is unusable here — see `session_id`'s memory-leakage note): chaining to a ~1.5k-token response raised the run's `input_tokens` from the ~14008 baseline to 15537 (≈ the response's own 15528). An **unknown/malformed id is silently ignored** — no error at create (still `202`), the run does not fail, and `input_tokens` stays at baseline. Validation appears to be value-tolerant load-if-present. |

> All five documented fields above were exercised on `hermes-test`
> (2026-05-23). Still **unconfirmed:** whether `model` or any other flags are
> accepted, and the `session_id` history semantics (see its note).
>
> **Technique:** prior-context fields were verified by **token accounting**, not
> content recall — the gateway's persistent-memory leakage makes "did it
> remember X?" unreliable (a fact leaks across runs regardless of chaining), but
> a loaded context visibly raises `usage.input_tokens` over the baseline. The
> baseline for a trivial run on this profile is ~14008 input tokens (mostly the
> agent's own system prompt/memory); it is profile- and prompt-specific, so
> compare deltas, not absolute values.

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
  transient `stopping`; a gated tool parks the run at `waiting_for_approval`
  (see Approval workflow).
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
| `approval.request` | `command`, `pattern_key`, `pattern_keys[]`, `description`, `choices[]` | Dangerous command gated; run parks at `waiting_for_approval`. See Approval workflow. |
| `approval.responded` | `choice`, `resolved` | Emitted after a `/approval` response. See Approval workflow. |

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
- **Approval events** (`approval.request`, `approval.responded`) fire when a
  dangerous command is gated — see the **Approval workflow** section below for
  the full event/request/response shapes. (They only fire when the profile is
  in `approvals.mode: manual` with a non-container backend and the agent
  attempts a command matching a dangerous pattern; a benign command runs
  ungated, which is why earlier benign probes never produced them.)

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

#### Approval workflow (dangerous-command gating)

Human-in-the-loop gating for dangerous tool commands. Server-side mechanism
(see `/docs/user-guide/security`): when the agent attempts a command matching a
dangerous pattern (`rm -r`, `mkfs`, `dd if=`, `DROP TABLE`, `> /etc/`,
`systemctl stop`, `curl | sh`, …) the run **pauses** and asks the caller to
approve. **Only fires** when the profile's `~/.hermes/config.yaml` has
`approvals.mode: manual` (not `off`/`smart`), no `--yolo`/`HERMES_YOLO_MODE`,
and a **non-container backend** (container backends skip the checks). **Verified
on `hermes-test` (2026-05-23)** with `rm -rf /tmp/...` (matches the pattern; not
on the always-on hardline blocklist).

Flow (deny path observed end-to-end; approve path pending a live approval):

1. Run is created normally and reaches `running`.
2. On hitting the gated tool, the run parks at status **`waiting_for_approval`**
   (`last_event: "approval.request"`). The poll response carries no approval
   detail beyond that — the detail is in the event stream.
3. The events stream emits **`approval.request`**:

   ```json
   {
     "event": "approval.request",
     "run_id": "run_...",
     "timestamp": 1779559698.69,
     "command": "rm -rf /tmp/hermes_probe_deny1",
     "pattern_key": "delete in root path",
     "pattern_keys": ["delete in root path"],
     "description": "delete in root path",
     "choices": ["once", "session", "always", "deny"]
   }
   ```

   There is **no approval/request id** — the pending approval is keyed by
   `run_id` (one outstanding approval per run).
4. Caller responds: **`POST /v1/runs/{run_id}/approval`** with
   `{"choice": "<once|session|always|deny>"}`. An invalid/absent choice returns
   `400`:

   ```json
   { "error": { "message": "Invalid approval choice; expected one of: once, session, always, deny",
       "type": "invalid_request_error", "param": null, "code": "invalid_approval_choice" } }
   ```

   A valid choice returns `200`:

   ```json
   { "object": "hermes.run.approval_response", "run_id": "run_...", "choice": "deny", "resolved": 1 }
   ```

   `resolved` is the count of pending approvals this call resolved.
   > ⚠️ `always` writes a **permanent** entry to the profile's
   > `command_allowlist` (config mutation); `session` auto-approves the pattern
   > for the rest of the gateway session. Prefer `once`/`deny` when probing.
5. The stream then emits **`approval.responded`** (`choice`, `resolved`),
   followed by `tool.completed`.

**Deny outcome:** the run **does not fail** — it ends `completed`.
`tool.completed` carries `"error": true` (and a `duration` that *includes* the
time spent waiting for the response), and the agent narrates the abort as normal
text (e.g. `output: "Understood. I have aborted that action."`).

**No auto-timeout observed:** despite the docs' `approvals.timeout: 60`, a run
sat `waiting_for_approval` for ~89s until an explicit response, with no
auto-deny. Treat a gated run as blocking **indefinitely** pending a response;
the documented timeout does not appear to apply to the API-server run flow.

**Approve outcome (verified 2026-05-23 with `choice: "once"`):** the gated tool
**executes** and the run resumes to `completed`. The only on-the-wire difference
from deny is `tool.completed` carrying **`"error": false`** (deny → `true`); the
agent then proceeds normally (e.g. `output: "OK."`) instead of narrating an
abort. Full sequence: `tool.started` → `approval.request` →
`approval.responded` (`choice:"once"`) → `tool.completed` (`error:false`) →
`message.delta`/`reasoning.available` → `run.completed`. The `/approval`
response is the same `hermes.run.approval_response` shape, with the echoed
`choice`. (Only `once` and `deny` were exercised; `session`/`always` were
deliberately skipped for their session/config side effects, but the server
accepts all four as valid choices.)

### Jobs API (background scheduled work) — note the `/api` prefix, not `/v1`

A lightweight CRUD surface for **scheduled / background agent runs** — cron-like
recurring tasks, one-shot deferred tasks, and watchdog scripts. Per the docs the
create body "accepts the same shape as `hermes cron`"; field semantics below
were confirmed against the `hermes cron create --help` CLI and live probing.

- **GET `/api/jobs`** — list scheduled jobs. Returns `{"jobs": [ <job>, … ]}`.
- **POST `/api/jobs`** — create a scheduled job. Returns `{"job": <job>}`.
- **GET `/api/jobs/{job_id}`** — fetch a job definition + last-run state.
  Returns `{"job": <job>}`.
- **PATCH `/api/jobs/{job_id}`** — partial update; sent fields are merged onto
  the existing job. Returns the full `{"job": <job>}`.
- **DELETE `/api/jobs/{job_id}`** — remove a job (also cancels any in-flight
  run). Returns `{"ok": true}` — **not** a job entity.
- **POST `/api/jobs/{job_id}/pause`** — pause without deleting. Returns
  `{"job": <job>}` (now `state:"paused"`, `enabled:false`).
- **POST `/api/jobs/{job_id}/resume`** — resume a paused job. Returns
  `{"job": <job>}` with `next_run_at` recomputed from the resume time.
- **POST `/api/jobs/{job_id}/run`** — trigger out of schedule. Returns
  `{"job": <job>}`. **Asynchronous:** it advances `next_run_at` to "now" for the
  scheduler's next tick rather than running synchronously — `last_run_at` /
  `last_status` / `repeat.completed` are *not* updated by the time the call
  returns. (CLI desc: "Run a job on the next scheduler tick.")

> **Not in `/v1/capabilities`.** Unlike the runs endpoints, the jobs endpoints
> are **not** advertised in the capabilities `endpoints` map or `features` flags
> (re-checked 2026-05-24). They live on a separate `/api` surface; discover them
> from the docs / this file, not from capabilities.

**Auth:** same bearer token as the rest of the server.

#### Error format — MIXED (a gotcha for the Transport error layer)

The jobs path serves **two different error envelopes** depending on the layer
that rejects the request — a client error-mapper built only for the `/v1`
nested shape will mis-parse the business errors:

- **Auth (401) uses the SAME nested `/v1`-style envelope** as the rest of the
  server (enforced by middleware *above* the jobs handler). Both a missing and a
  wrong bearer token return `401` with
  `{"error":{"message":"Invalid API key","type":"invalid_request_error","code":"invalid_api_key"}}`.
  So `401`→`AuthenticationError` keys on status as usual and even parses with the
  existing nested parser.
- **Jobs business errors (400 / 404 / 500) use a FLAT string** envelope
  `{"error": "<message>"}` — no `type`/`code`/`param`. Observed (2026-05-24):

| Status | Body | Trigger |
|--------|------|---------|
| `400 Bad Request` | `{"error": "Invalid job ID format"}` | id not 12 hex chars (e.g. `nonexistent123`). |
| `404 Not Found` | `{"error": "Job not found"}` | well-formed but unknown id (GET / run / etc.). |
| `400 Bad Request` | `{"error": "Name is required"}` | create with no `name` (validated **first**, before schedule). |
| `400 Bad Request` | `{"error": "Schedule is required"}` | create with `name` but no `schedule`. |
| `500 Internal Server Error` | `{"error": "Invalid schedule '…'. Use:\n  - Duration: '30m', …"}` | create with an unparseable `schedule` string (note: **500**, not 400; message lists the accepted schedule syntaxes). |

So `APIError`'s message extraction must accept **either** a nested
`error.message` (auth) **or** a flat string `error` (jobs business errors). Note
the validation `500` is a normal user-input rejection here, not a server fault.

#### PATCH, deliver, and pause/resume edge behavior (verified 2026-05-24)

- **PATCH mutates the full create-able field set**, not just `prompt`: a single
  PATCH changed `name`, `repeat`, `deliver`, **and** `schedule` together — the
  new schedule string was **re-parsed** (interval → cron) and `next_run_at`
  **recomputed** to the next occurrence. (Override fields stay ignored — see the
  create-request warning.)
- **`deliver` is NOT validated at create/patch:** a bogus `"deliver":"not-a-target"`
  was accepted and stored verbatim with `200`. Any delivery-target validation
  happens at delivery time, not on write — don't expect a `400` for a bad target.
- **`pause`/`resume` are idempotent:** pausing an already-`paused` job and
  resuming an already-`scheduled` job both return `200` with the job in the
  expected state (no error).

#### Job entity (observed 2026-05-24, `hermes-test`)

Create/get/list/patch/pause/resume/run all return this same object (singular
under `"job"`, list under `"jobs"`). The `id` is **12 lowercase hex chars** (no
`run_`-style prefix), e.g. `0ec925dc7192`.

```json
{
  "id": "0ec925dc7192",
  "name": "Hello world",
  "prompt": "Say \"hello world\" in a creative way.",
  "skills": [],
  "skill": null,
  "model": null,
  "provider": null,
  "base_url": null,
  "script": null,
  "no_agent": false,
  "context_from": null,
  "schedule": { "kind": "cron", "expr": "0 9 * * *", "display": "0 9 * * *" },
  "schedule_display": "0 9 * * *",
  "repeat": { "times": null, "completed": 2 },
  "enabled": true,
  "state": "scheduled",
  "paused_at": null,
  "paused_reason": null,
  "created_at": "2026-05-22T11:51:06.929692-07:00",
  "next_run_at": "2026-05-25T09:00:00-07:00",
  "last_run_at": "2026-05-24T09:00:27.846643-07:00",
  "last_status": "ok",
  "last_error": null,
  "last_delivery_error": null,
  "deliver": "local",
  "origin": null,
  "enabled_toolsets": null,
  "workdir": null,
  "profile": null
}
```

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | 12-hex job id. |
| `name` | string | Human-friendly name. **Required on create.** |
| `prompt` | string\|null | The task instruction. Optional (a `--no-agent` script job needs none). |
| `skills` | array | Attached skill names (`--skill`, repeatable). `skill` (singular) is a separate scalar slot, `null` when unused. |
| `model` / `provider` / `base_url` | string\|null | Per-job LLM override ("provider override" in the docs). All `null` = use the profile's configured model. **Read-only via this API** — ignored in create/PATCH bodies (see the create-request warning). |
| `script` | string\|null | Path under `~/.hermes/scripts/`. Default: script stdout is injected into the agent prompt each run. |
| `no_agent` | boolean | Skip the LLM entirely — run `script` and deliver its stdout verbatim (watchdog pattern). |
| `context_from` | string\|null | (Unprobed.) Source to pull run context from. |
| `schedule` | object | Tagged-union by `kind` — see below. |
| `schedule_display` | string | Human-readable schedule (mirrors `schedule.display`). |
| `repeat` | object | `{ "times": <int\|null>, "completed": <int> }`. `times` = max runs (`null` = unbounded / from `--repeat`); `completed` increments per executed run. |
| `enabled` | boolean | `false` while paused. |
| `state` | string | Lifecycle: `scheduled` ↔ `paused` observed; see below. |
| `paused_at` | string\|null | ISO-8601 timestamp set on pause, cleared on resume. |
| `paused_reason` | string\|null | Optional reason; `null` for manual pause. |
| `created_at` / `next_run_at` / `last_run_at` | string\|null | **ISO-8601 with offset** (e.g. `…-07:00`), *not* the epoch-float style the runs API uses. `last_run_at` is `null` until the first execution. |
| `last_status` | string\|null | Outcome of the last run (`"ok"` observed); `null` before first run. |
| `last_error` / `last_delivery_error` | string\|null | Error detail from the last execution / delivery attempt. |
| `deliver` | string | Delivery target: `origin`, `local`, `telegram`, `discord`, `signal`, or `platform:chat_id`. **Defaults to `"local"`** when omitted on create. |
| `origin` | object\|null | Originating channel info (for `deliver:"origin"`); `null` for locally created jobs. |
| `enabled_toolsets` | array\|null | Toolset allowlist; `null` = default set. (Unprobed.) |
| `workdir` | string\|null | Absolute cwd for the run; injects `AGENTS.md`/`CLAUDE.md`/`.cursorrules` from there. `null` = no project context. |
| `profile` | string\|null | Hermes profile to run under; `null` = scheduler's existing profile. |

#### Schedule object (`schedule` is a tagged union on `kind`)

The create `schedule` string is parsed into one of three stored shapes. The
parser accepts four input syntaxes (per the 500 error message) that map to these
three kinds:

| `kind` | Stored fields | Created from (input syntax) |
|--------|---------------|------------------------------|
| `once` | `run_at` (ISO-8601), `display` | a bare **duration** `"30m"` / `"2h"` / `"1d"` (→ `run_at` = now + duration, `display:"once in 30m"`), **or** an absolute **timestamp** `"2027-02-03T14:00:00"` (`display:"once at 2027-02-03 14:00"`). One-shot. |
| `interval` | `minutes` (int), `display` | `"every 30m"` / `"every 2h"` (→ `minutes`, `display:"every 120m"`). Recurring. |
| `cron` | `expr` (string), `display` | a cron expression `"0 9 * * *"` (`expr` == `display`). Recurring. |

#### Create request (POST `/api/jobs`)

Body keys mirror `hermes cron create` flags. **Confirmed accepted:** `name`
(required), `schedule` (required, the syntaxes above), `prompt`, `repeat`
(integer), `deliver`. CLI-backed and presumably accepted (not individually
re-probed): `skills`/`skill`, `script`, `no_agent`. Create returns
**HTTP `200`** (not the runs API's `202`) with `{"job": <job>}`; new jobs start
`state:"scheduled"`, `enabled:true`, `repeat.completed:0`, `last_*` null.

> ⚠️ **`model`, `provider`, `base_url`, `workdir`, `profile`, and `context_from`
> are NOT settable via the API** (verified 2026-05-24): passing them in either
> the **create** body *or* a **PATCH** body is silently ignored — the fields
> stay `null` in the response (no error). The entity exposes these slots, but the
> HTTP API does not populate them under these key names; they appear to be
> CLI/config-only (`hermes cron create --workdir/--profile`, etc.). A client must
> not assume a job it creates can carry a per-job model/provider override or
> working directory through this API.

Minimal example:

```sh
toys gateway probe POST /api/jobs \
  --body '{"name":"probe","schedule":"every 2h","prompt":"do a thing"}'
```

#### Status lifecycle (run behavior verified live 2026-05-24)

- `scheduled` — active, waiting for `next_run_at`.
- `paused` — via `/pause`; sets `enabled:false` + `paused_at`. `/resume` returns
  it to `scheduled`, clears `paused_at`, and recomputes `next_run_at`.
- **There is no lingering terminal `state` — exhausted jobs are DELETED.** This
  was the key live finding, and it matters for the client:
  - A **`once` job is removed after it fires.** After its single run the job is
    gone: `GET /api/jobs/{id}` returns `404 Job not found` and it drops off the
    list. There is no `completed`/`done` state to observe.
  - A **capped recurring job** (`repeat.times` set) **runs `times` times, then is
    removed.** Verified with a `repeat:2` interval job: after run #1 it survived
    (`completed:1`, `state:"scheduled"`, `enabled:true`); after run #2 reached the
    cap it was deleted (`404`). A `repeat:1` job likewise vanished after one run.
  - An **uncapped recurring job** (`repeat.times: null`) just increments
    `repeat.completed` and stays `scheduled`, with `next_run_at` recomputed to the
    next occurrence. (Observed on the "Hello world" cron job: `completed` 2→3,
    `last_run_at` updated, `last_status:"ok"`, `state` stayed `scheduled`.)
- **A successful run** sets `last_run_at` (ISO-8601), `last_status:"ok"`, leaves
  `last_error`/`last_delivery_error` `null`, and bumps `repeat.completed`.
  `last_status` is the signal for the most recent run's outcome. (A failing-run
  `last_status`/`last_error` shape was **not** probed — would need a deliberately
  broken job.)
- **`/run` is asynchronous and so is the scheduler.** `/run` advances
  `next_run_at` to "now"; the gateway's in-process scheduler (`hermes cron status`
  → "Gateway is running — cron jobs will fire automatically") then picks the job
  up on a later tick — a pong run took on the order of ~20s to land after `/run`,
  not instant. The scheduler also **fires overdue jobs on startup**: a job whose
  persisted `next_run_at` was already in the past ran shortly after the gateway
  came up, then recomputed its next occurrence.

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
  cache). Useful for safely retrying mutating calls. **Scope verified from
  source + live probing (2026-05-25):**
  - Honored on **exactly two** operations: **non-streaming**
    `POST /v1/chat/completions` and **non-streaming** `POST /v1/responses`.
    The **streaming** variants of both, **all** of `/v1/runs*`, and **every**
    `/api/jobs` mutation **ignore** the header (the streaming branch returns
    before the check; the runs/jobs handlers never read it). Probed: two
    `/v1/runs` with the same key returned **different** `run_id`s.
  - Server impl is an in-memory `_IdempotencyCache`: TTL **300 s**, max **1000**
    entries, LRU eviction. Cache key = the header value **alone**; it also
    stores a sha256 **fingerprint** of a subset of body fields (chat:
    `model, messages, tools, tool_choice, stream`; responses: `input,
    instructions, previous_response_id, conversation, model, tools`).
  - **Hit** (same key + matching fingerprint): the cached agent result is
    returned **without re-running the model** (probed: ~2–3 ms vs ~1.3–2.2 s).
  - **Same key, different fingerprint**: it **silently recomputes** (no 409/422
    like Stripe) **and overwrites** the stored entry — last-write-wins, **one
    entry per key**. Probed: reusing a key with a changed body re-ran the model
    and a later request for the original body re-ran *again* (the original entry
    was clobbered).
  - Concurrent in-flight requests with the same (key, fingerprint) **coalesce**
    onto one computation (`asyncio` task + `shield`).
  - **No replay signal of any kind.** A replayed response has the **same HTTP
    status** (200), **no** `Idempotency-*`/replay header, and **no** body
    marker. The cache memoizes only the agent `(result, usage)`, **not** the
    HTTP envelope: the `id` (`chatcmpl-…`/`resp_…`) is **regenerated every
    call** and `created`/`created_at` is a per-call `int(time.time())` (so they
    differ on a replay — but they also differ on any recompute, i.e. they are
    *fresh values*, not a dedup indicator). A caller therefore **cannot detect**
    from the response whether a given call was served from the cache.
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
