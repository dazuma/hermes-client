# Hermes API Server — wire reference

The server-side contract this client codes against: endpoints, request/response
shapes, error envelopes, streaming framing, and observed behavior. Captured here
so future sessions don't re-fetch and re-probe.

**Scope vs. `DESIGN.md`.** This file describes **what the server does on the
wire**. `DESIGN.md` describes **how the client wraps it** (resource methods,
entity classes, return values). Wire facts live *here* and are cross-referenced
from `DESIGN.md`; don't duplicate them back.

**Sources & confidence.** Unless a statement is marked **(unverified)**, it
reflects the published docs and/or direct evidence — live probing of the
`hermes-test` profile via `toys gateway`, and/or the gateway source at
`gateway/platforms/api_server.py`. Dates are given only where a finding is
recent or notably tentative.
- Published docs: <https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server> (snapshot 2026-05-20; thin — endpoints + prose, almost no field schemas).
- Last live probe: 2026-05-25 (`hermes-test`, a real `gemini-flash-lite` model).
- **Prior-context fields are verified by token accounting**, not content recall:
  the gateway's persistent memory leaks facts across runs regardless of chaining,
  so "did it remember X?" is unreliable; a loaded context instead shows up as a
  rise in `usage.input_tokens` over the trivial-run baseline (~14010 on this
  profile — profile/prompt-specific, so compare deltas, not absolutes).

---

## Server basics

### Overview & enabling

The API server exposes hermes-agent as an **OpenAI-compatible HTTP endpoint**:
any frontend that speaks the OpenAI format can use it as a backend. Started with
`hermes gateway`; listens on `http://127.0.0.1:8642` by default. Enable it in
`~/.hermes/.env`:

```
API_SERVER_ENABLED=true
API_SERVER_KEY=change-me-local-dev
API_SERVER_CORS_ORIGINS=http://localhost:3000  # optional
```

The agent runs **server-side**: per `/v1/capabilities`, the runtime is
`server_agent` mode with `tool_execution: server` — the server builds a
server-side Hermes agent and executes tools on the API-server host. So
`chat`/`responses`/`runs` make real LLM calls (latency, cost); discovery and
health are cheap and offline-friendly.

### Authentication

- Bearer token via `Authorization: Bearer <token>`; configured server-side as
  `API_SERVER_KEY`. Required for non-loopback addresses.
- Missing/invalid token → `401` with `code: "invalid_api_key"` (see Error model).

### Configuration variables (server-side env)

These are server settings, not client config, but they pin the defaults the
client must match (port 8642, bearer auth, advertised model name).

| Variable | Default | Purpose |
|----------|---------|---------|
| `API_SERVER_ENABLED` | false | Enable the server |
| `API_SERVER_PORT` | 8642 | HTTP port |
| `API_SERVER_HOST` | 127.0.0.1 | Bind address |
| `API_SERVER_KEY` | (none) | Bearer token |
| `API_SERVER_CORS_ORIGINS` | (none) | Browser origin allowlist |
| `API_SERVER_MODEL_NAME` | (profile name) | Advertised model name |

---

## Cross-cutting conventions

### Error model

Non-2xx responses carry **three different envelope shapes** depending on which
layer rejected the request. A client error-mapper must tolerate all three and
**key the error class off HTTP status, not the body** (`type` is not a reliable
discriminator — it is `invalid_request_error` for nearly everything, including
`401`).

**1. `/v1` application errors — nested OpenAI-style JSON.** Auth failures, body
validation, and missing resources on the `/v1` surface:

```json
{ "error": { "message": "…", "type": "invalid_request_error", "param": null, "code": null } }
```

`message` and `type` are always present; `param` and `code` may be `null` or
omitted entirely. Treat them as best-effort. Observed cases:

| Status | `code` | Trigger |
|--------|--------|---------|
| `401` | `invalid_api_key` | Missing or wrong bearer token (`"Invalid API key"`). |
| `400` | `null`/absent | Missing/invalid body field — e.g. `"Missing 'input' field"`, `"'input' must be a string or array"`, `"Missing or invalid 'messages' field"`, `"Invalid JSON in request body"`. |
| `404` | `null` | `GET /v1/responses/{bad}` → `"Response not found: …"`. |
| `404` | `run_not_found` | Unknown/evicted run on any `/v1/runs/{id}*` route (existence is checked **before** the body, so a bad `run_id` 404s regardless of body). |
| `404` | `null` | `POST /v1/responses` with an unknown `previous_response_id` → `"Previous response not found: …"`. |
| `400` | `invalid_approval_choice` | `POST /v1/runs/{id}/approval` with a bad/absent `choice`. |
| `400` | `null` | `POST /v1/runs` with non-array `conversation_history`. |

**2. Jobs business errors — FLAT string JSON.** The `/api/jobs` handlers (below
the auth middleware) return a bare-string envelope — **no `type`/`code`/`param`**:

```json
{ "error": "Job not found" }
```

| Status | Body | Trigger |
|--------|------|---------|
| `400` | `"Invalid job ID format"` | id not 12 hex chars. |
| `404` | `"Job not found"` | well-formed but unknown id (GET / run / etc.). |
| `400` | `"Name is required"` | create with no `name` (validated **first**). |
| `400` | `"Schedule is required"` | create with `name` but no `schedule`. |
| `500` | `"Invalid schedule '…'. Use:\n  - Duration: '30m', …"` | unparseable `schedule` — note **500**, not 400; it is still a user-input rejection, not a server fault. The message lists the accepted syntaxes. |

> Jobs **auth** (`401`) is the exception: it is enforced by middleware *above*
> the jobs handler, so it uses the **nested `/v1`-style** envelope
> (`{"error":{"message":"Invalid API key",…,"code":"invalid_api_key"}}`), not the
> flat shape. So `401` parses with the nested parser everywhere.

So message extraction must accept **either** a nested `error.message` **or** a
flat string `error`.

**3. Router/framework errors — bare text, not JSON.** Below the application:

- `404: Not Found` — unrouted path.
- `405: Method Not Allowed` — wrong method on a real route.

Parse defensively and fall back to the raw body for these.

### Streaming transport (SSE framing)

All streaming is Server-Sent Events, but the three streaming endpoints frame
events **differently** — the client's stream parser must branch by endpoint:

| Endpoint | SSE `event:` line? | Type carried in | Terminator |
|----------|--------------------|-----------------|------------|
| Chat completions | No (except the one named `hermes.tool.progress` frame) | n/a — frames are `chat.completion.chunk` objects | literal `data: [DONE]` |
| Responses | No | a `type` field in each `data:` payload (+ 0-based `sequence_number`) | none — stream ends after `response.completed` |
| Runs events | No | an `"event"` string field in each `data:` payload | none — stream ends after the terminal frame |

Per-endpoint event catalogs are in each endpoint's section below.

### Idempotency-Key

`Idempotency-Key` request header for safe retries of mutating calls. Verified
from source + probing (2026-05-25):

- **Honored on exactly two operations:** **non-streaming** `POST /v1/chat/completions`
  and **non-streaming** `POST /v1/responses`. The **streaming** variants of both,
  **all** `/v1/runs*`, and **every** `/api/jobs` mutation **ignore** it (streaming
  returns before the check; runs/jobs handlers never read it — two `/v1/runs`
  with the same key returned different `run_id`s).
- Impl is an in-memory `_IdempotencyCache`: TTL **300 s**, max **1000** entries,
  LRU. Key = the header value **alone**, plus a sha256 **fingerprint** of a body
  subset (chat: `model, messages, tools, tool_choice, stream`; responses: `input,
  instructions, previous_response_id, conversation, model, tools`).
- **Hit** (same key + matching fingerprint): cached agent result returned without
  re-running the model (~2–3 ms vs ~1.3–2.2 s).
- **Same key, different fingerprint:** silently **recomputes and overwrites** the
  entry (no 409/422; last-write-wins, one entry per key).
- Concurrent in-flight requests with the same (key, fingerprint) **coalesce** onto
  one computation.
- **No replay signal of any kind.** Same HTTP status (200), no `Idempotency-*`
  header, no body marker. Only the agent `(result, usage)` is memoized — the `id`
  (`chatcmpl-…`/`resp_…`) is regenerated and `created`/`created_at` is per-call,
  so they differ on a replay (but also on any recompute — they are fresh values,
  not a dedup indicator). A caller **cannot detect** a cache hit from the response.

### Session & memory headers

Two optional request headers, advertised in `/v1/capabilities`
(`session_continuity_header` / `session_key_header`). Both are **independent**
(send either, both, or neither) and both **require API-key auth** — an
unauthenticated client on a local server cannot use them (→ `403`).

| Header | Meaning |
|--------|---------|
| `X-Hermes-Session-Id` | Continues an existing short-term transcript. On chat, history is loaded from `state.db` for that id instead of from the request body. Rotates when the caller starts a new transcript (`/new` semantics). |
| `X-Hermes-Session-Key` | Stable per-channel identifier that scopes **long-term memory** (e.g. Honcho) **across** transcripts. Max **256** chars. |

Validation (when a header is honored): no API key configured → `403`; control
chars (`\r`/`\n`/`\0`) → `400` (`"Invalid session ID"` / `"Invalid session key"`);
over-length key → `400` (`"Session key too long"`).

Observed request/response behavior:

- **`POST /v1/chat/completions`** honors **both** on the request. With no
  `X-Hermes-Session-Id`, the server derives a stable session id from a fingerprint
  of (system prompt + first user message), so consecutive turns of one frontend
  conversation map to one session.
- **`POST /v1/responses`** chains via `previous_response_id`/`conversation`, not
  these headers — sending `X-Hermes-Session-Id` has **no observable continuation
  effect**.
- **Both** POST endpoints **return** the headers on the response (including SSE):
  `X-Hermes-Session-Id` is **always present** (server-generated when none was
  sent); `X-Hermes-Session-Key` comes back **only when one was sent**.
- **`GET /v1/responses/{id}`** returns **neither**.

API-server sessions persist to `state.db`, so they appear in `hermes sessions list`
alongside CLI/gateway ones.

### Security & CORS headers

- Security response headers: `X-Content-Type-Options: nosniff`,
  `Referrer-Policy: no-referrer`.
- CORS is **disabled by default**; origins must be explicitly allowlisted
  (`API_SERVER_CORS_ORIGINS`). Allowed request headers:
  `Authorization, Content-Type, Idempotency-Key`. Preflight uses
  `Access-Control-Max-Age: 600`.

---

## Endpoints

### Discovery — `GET /v1/models`, `GET /v1/capabilities`

Cheap, offline-friendly (no LLM call).

**`GET /v1/models`** — lists the agent as one model; `id` is the profile name
(overridable via `API_SERVER_MODEL_NAME`):

```json
{
  "object": "list",
  "data": [
    { "id": "hermes-test", "object": "model", "created": 1779731115,
      "owned_by": "hermes", "permission": [], "root": "hermes-test", "parent": null }
  ]
}
```

The envelope is **hardcoded server-side** to this single model — never paginated,
never more than one entry — and `permission` is a **literal empty `[]`** (never
populated, so its element shape is undiscoverable here). The `logprobs: []` arrays
in chat/Responses output are likewise hardcoded empty (the server reads no
`logprobs`/`top_logprobs` request param). Treat both as structurally always-empty.

**`GET /v1/capabilities`** — machine-readable feature description. The `endpoints`
map and `features` flags are the authoritative source for what this server
build supports. **Jobs are not listed here** (see Jobs API). Full observed body:

```json
{
  "object": "hermes.api_server.capabilities",
  "platform": "hermes-agent",
  "model": "hermes-test",
  "auth": { "type": "bearer", "required": true },
  "runtime": {
    "mode": "server_agent",
    "tool_execution": "server",
    "split_runtime": false,
    "description": "…tools execute on the API-server host…"
  },
  "features": {
    "chat_completions": true,
    "chat_completions_streaming": true,
    "responses_api": true,
    "responses_streaming": true,
    "run_submission": true,
    "run_status": true,
    "run_events_sse": true,
    "run_stop": true,
    "run_approval_response": true,
    "tool_progress_events": true,
    "approval_events": true,
    "session_continuity_header": "X-Hermes-Session-Id",
    "session_key_header": "X-Hermes-Session-Key",
    "cors": false
  },
  "endpoints": {
    "health":           { "method": "GET",  "path": "/health" },
    "health_detailed":  { "method": "GET",  "path": "/health/detailed" },
    "models":           { "method": "GET",  "path": "/v1/models" },
    "chat_completions": { "method": "POST", "path": "/v1/chat/completions" },
    "responses":        { "method": "POST", "path": "/v1/responses" },
    "runs":             { "method": "POST", "path": "/v1/runs" },
    "run_status":       { "method": "GET",  "path": "/v1/runs/{run_id}" },
    "run_events":       { "method": "GET",  "path": "/v1/runs/{run_id}/events" },
    "run_approval":     { "method": "POST", "path": "/v1/runs/{run_id}/approval" },
    "run_stop":         { "method": "POST", "path": "/v1/runs/{run_id}/stop" }
  }
}
```

### Health — `GET /health`, `GET /health/detailed`

At the **root**, not under `/v1`. Cheap, offline-friendly.

```json
// GET /health
{ "status": "ok", "platform": "hermes-agent" }
```

```json
// GET /health/detailed
{
  "status": "ok",
  "platform": "hermes-agent",
  "gateway_state": "running",
  "platforms": {
    "api_server": { "state": "connected", "error_code": null,
                    "error_message": null, "updated_at": "2026-05-25T17:45:06.721064+00:00" }
  },
  "active_agents": 0,
  "exit_reason": null,
  "updated_at": "2026-05-25T17:45:06.721394+00:00",
  "pid": 98928
}
```

### Chat Completions — `POST /v1/chat/completions`

Standard OpenAI Chat Completions; **stateless** by default (opt-in continuity via
the session headers above).

**Request fields** (the agent's actual model is server-side, so most OpenAI knobs
are cosmetic):

| Field | Type | Req? | Notes |
|-------|------|------|-------|
| `messages` | array | required | OpenAI messages. Inline images via `image_url` content parts (`http(s)` or `data:image/…` base64 URLs). |
| `stream` | boolean | optional | `true` → SSE (see below). Default false. |
| `model` | string | optional | Cosmetic; the server uses its configured model. |
| `tools` / `tool_choice` | — | optional | Accepted (part of the idempotency fingerprint); tools execute server-side regardless. |
| `n` | int | optional | **Ignored** — the server always returns a single `choices[0]` (probed 2026-05-24: `n` up to 5, deterministic *and* high-temp creative prompts, never produced `index > 0`). |

Honors `Idempotency-Key` (non-streaming) and the session headers.

**Non-streaming response** — standard `chat.completion`, **always one choice**
(see `n`). Note `usage` uses `prompt_tokens`/`completion_tokens` (**contrast** the
Responses API). `id` is `chatcmpl-` + 29 hex chars.

```json
{
  "id": "chatcmpl-1c0002b29faf4b909555b4e257d8d",
  "object": "chat.completion",
  "created": 1779731139,
  "model": "hermes-test",
  "choices": [
    { "index": 0, "message": { "role": "assistant", "content": "hello" }, "finish_reason": "stop" }
  ],
  "usage": { "prompt_tokens": 14010, "completion_tokens": 1, "total_tokens": 14011 }
}
```

**Streaming** — **unnamed** SSE frames whose `data:` is a `chat.completion.chunk`.
First chunk carries `delta.role`, subsequent chunks `delta.content`, the final
chunk has an empty `delta`, `finish_reason: "stop"`, and a `usage` block. All
chunks share one stable `id`. Terminates with a literal `data: [DONE]`.

- **`hermes.tool.progress`** — the one **named** frame in the chat stream
  (`event: hermes.tool.progress`), surfacing server-side tool execution so it
  doesn't pollute assistant text. Interleaved **between** the role chunk and the
  content chunks (tools run before the text). Unlike Responses events it has **no
  `type` and no `sequence_number`**. Each tool call emits **two** frames keyed by
  a `toolCallId` (`call_…`): a `status: "running"` frame `{ tool, emoji, label,
  toolCallId, status }` and a `status: "completed"` frame `{ tool, toolCallId,
  status }` (no `emoji`/`label`). `tool` is the tool name (e.g. `search_files`,
  `terminal`); `label` is a short human descriptor. A turn may run multiple tools.
  `status` is **lifecycle only**, not success/failure — tool failures surface as
  the tool's result content (which the model narrates), never as an `error`
  status. These frames are **not** `chat.completion.chunk`s (no `choices`/`delta`).

### Responses API — `POST` / `GET` / `DELETE` `/v1/responses`

OpenAI Responses API with **server-side conversation persistence**.

**`POST /v1/responses`** request fields:

| Field | Type | Req? | Notes |
|-------|------|------|-------|
| `input` | string \| array | required | A string, or an array of strings / `{role, content}` objects. Inline images via `input_image` content parts. The last input message is the new user turn; earlier ones become history. |
| `instructions` | string | optional | System directive layered over the agent prompt. Carried forward from the previous response when omitted on a chained turn. |
| `previous_response_id` | string | optional | Chains to a stored response (loads its `conversation_history`). **Unknown id → `404`** `"Previous response not found"` (contrast Runs, which silently ignores). |
| `conversation` | string | optional | Names a conversation; resolves to its latest response id (no error if new). **Mutually exclusive** with `previous_response_id` → `400` `"Cannot use both …"`. |
| `conversation_history` | array | optional | Explicit OpenAI-style history for stateless clients. Validated (each entry needs `role` + `content`, else `400`). **Takes precedence over** `previous_response_id`. |
| `store` | boolean | optional | Whether to persist the response for later GET / chaining. **Default `true`.** |
| `truncation` | string | optional | `"auto"` caps `conversation_history` to the last 100 messages when it exceeds 100. |
| `stream` | boolean | optional | `true` → SSE (see below). Default false. |
| `model` | string | optional | Cosmetic. |

Honors `Idempotency-Key` (non-streaming). Session headers are **returned** but not
honored as request-side continuation (see Session headers).

**Non-streaming response / `GET /v1/responses/{id}`** — same shape. `usage` uses
`input_tokens`/`output_tokens` (**contrast** Chat). `id` is `resp_` + hex.

```json
{
  "id": "resp_6b27d0b70fea42c5ab4c0b7ca219",
  "object": "response",
  "status": "completed",
  "created_at": 1779731142,
  "model": "hermes-test",
  "output": [
    { "type": "message", "role": "assistant",
      "content": [ { "type": "output_text", "text": "hello" } ] }
  ],
  "usage": { "input_tokens": 14010, "output_tokens": 1, "total_tokens": 14011 }
}
```

**`DELETE /v1/responses/{id}`** → a small confirmation object (not the response):

```json
{ "id": "resp_6b27d0b70fea42c5ab4c0b7ca219", "object": "response", "deleted": true }
```

A later GET of a deleted/unknown id → `404` `"Response not found: …"`.

> **Stored responses are capped** at ~100 (SQLite, LRU eviction); older responses
> may no longer be retrievable.

**Streaming** — **named** events; each `data:` payload repeats the name in a
`type` field and carries a monotonic 0-based `sequence_number`. **No `[DONE]`
sentinel** — the stream ends after `response.completed`. Order for a simple text
turn: `response.created` (0) → `response.output_item.added` (1) →
`response.output_text.delta` (2, one per delta) → `response.output_text.done` (3)
→ `response.output_item.done` (4) → `response.completed` (5, terminal).

- `response.created` carries the `response` object with `id` (`resp_…`, used for
  `previous_response_id`), `status: "in_progress"`, `model`, `created_at`, empty
  `output: []`.
- Delta events thread an `item_id` (`msg_…`), `output_index`, `content_index`.
  `…output_text.delta` carries the incremental `delta` string; `…output_text.done`
  carries the assembled `text`. (Both carry a `logprobs` array, **hardcoded empty**
  server-side.)
- `response.output_item.added` / `.done` nest the item under an **`item`** key
  (`{ id, type, status, role, content }`) alongside `output_index` — `added` is
  `in_progress` with empty `content`, `done` is `completed` with the assembled
  `content`.
- **`response.completed` carries the full final `response`** — complete `output`
  array and a `usage` block (`input_tokens`/`output_tokens`/`total_tokens`). A
  stream aggregator can take the final object straight from this event.
- **Tool-executing turn:** uses the **same** `output_item.added`/`.done` events —
  **no `hermes.tool.progress`** (chat-only) and **no separate function-call event
  types**. Each tool call/result is an ordinary output item with its own
  `output_index`: a `function_call` item (`{ id: fc_…, type, status, name, call_id,
  arguments }`) then a `function_call_output` item (`{ id: fco_…, type, call_id,
  status, output }`), per tool, then the final `message` item — all echoed in
  `response.completed.output`. The `arguments` JSON string arrives **whole** in the
  `added` event (no argument-delta streaming). `status` is lifecycle-only (a tool
  that times out still reports `completed`).
- **Representation differences** (same logical data, different shape by transport):
  - A `function_call_output`'s **`output`** is an **array of content parts**
    (`[{ type: "input_text", text }]`) in **every streaming** form (per-item events
    *and* `response.completed.output`), but a **raw JSON string** in the
    **non-streaming** POST/GET bodies.
  - Output-item **`id`** (`fc_/fco_/msg_…`) and **`status`** appear **only** on
    items inside per-item streaming events; they are **absent** from the
    non-streaming `output` array *and* from the streamed `response.completed.output`.

### Runs API — `POST /v1/runs` (+ status / events / stop / approval)

A streaming-friendly alternative for long-form, multi-step agent execution:
create a run, then subscribe to its progress stream. Designed so clients can
**attach/detach without losing state** — the run keeps executing server-side. Use
it when you want progress tracking via a `run_id` rather than an inline stream.

Run feature flags (`/v1/capabilities`): `run_submission`, `run_status`,
`run_events_sse`, `run_stop`, `run_approval_response`, `tool_progress_events`,
`approval_events`.

Endpoints:

- **POST `/v1/runs`** — create; returns `202 Accepted`.
- **GET `/v1/runs/{run_id}`** — poll state.
- **GET `/v1/runs/{run_id}/events`** — SSE progress stream.
- **POST `/v1/runs/{run_id}/stop`** — cooperative interrupt.
- **POST `/v1/runs/{run_id}/approval`** — answer a tool-approval request. **Not on
  the published docs page**; discovered via `/v1/capabilities`. See Approval workflow.

`run_id` is `run_` + 32 lowercase hex chars (no dashes), e.g.
`run_0591466636124693b94936a2314f20e5`. Unknown/evicted id on any of these →
`404 run_not_found` (checked before the body).

#### Create request (POST `/v1/runs`)

All five fields below were exercised on `hermes-test` (2026-05-23). Whether
`model` or other flags are accepted is **(unverified)**.

| Field | Type | Req? | Notes |
|-------|------|------|-------|
| `input` | string | required | The user prompt for the run. |
| `instructions` | string | optional | System directive over the agent prompt. (`instructions:"Respond with exactly one word: BANANA"` → `output: "BANANA"`.) |
| `conversation_history` | array | optional | OpenAI-style messages, **loaded into context** (verified by token accounting). **Validated:** non-array → `400` `"'conversation_history' must be an array of message objects"`. |
| `previous_response_id` | string | optional | Loads a stored `/v1/responses` context into the run (verified by token accounting). **Unknown/malformed id is silently ignored** — no error, still `202`, `input_tokens` stays at baseline (contrast Responses, which `404`s). |
| `session_id` | string | optional | A **correlation label**: stored and echoed in the poll response; defaults to the `run_id` when omitted. **Not** inline conversation context. Whether it scopes a *searchable* history store is **(unverified/inconclusive)** — retrieval on `hermes-test` was non-deterministic, consistent with the known persistent-memory flakiness; confirm from server source if it matters. |

Create response (`202`):

```json
{ "run_id": "run_0591466636124693b94936a2314f20e5", "status": "started" }
```

#### Poll response (GET `/v1/runs/{run_id}`)

```json
{
  "object": "hermes.run",
  "run_id": "run_0591466636124693b94936a2314f20e5",
  "status": "completed",
  "created_at": 1779510796.504134,
  "updated_at": 1779510798.6846,
  "session_id": "run_0591466636124693b94936a2314f20e5",
  "model": "hermes-test",
  "last_event": "run.completed",
  "output": "hello",
  "usage": { "input_tokens": 14010, "output_tokens": 1, "total_tokens": 14011 }
}
```

- `created_at`/`updated_at`: **epoch seconds as floats** (contrast Jobs' ISO-8601).
- `model`: the profile name. `last_event`: name of the most recent SSE event.
- `output`: assembled final assistant text, once terminal.
- **`output` and `usage` are present only on a `completed` run** — a `cancelled`
  or `failed` run omits both (see Stop). Don't assume they exist.

#### Status lifecycle

- **Non-terminal:** `started` (create response) → `running` (`last_event` empty at
  the very start). `stop` adds a transient `stopping`; a gated tool parks the run
  at `waiting_for_approval`.
- **Terminal:** `completed`, `cancelled` (after `stop`), `failed`.
- Records are retained only **briefly** after terminal (for polling/UI
  reconciliation), then evicted → poll and stop both return `404 run_not_found`.
  The status record outlives the event buffer (see Events).

#### Events stream (GET `/v1/runs/{run_id}/events`)

Plain `data:` JSON frames — **no `event:` line, no `[DONE]`**; the type lives in an
`"event"` field. Every frame carries `event`, `run_id`, and `timestamp` (epoch
float). Subscribing *after* creation **replays from the first event** (the
attach/detach design); there is **no `run.started`** frame — the stream begins at
the first content event, and `create`'s `status: "started"` is the only start
signal.

Replay is **retention-bounded**: it survives reaching a terminal state (both
`completed` and `cancelled` replay) but only briefly — re-verified 2026-05-23,
a `cancelled` run replayed `200` once, then `404`ed seconds later. A `404` here is
a **retention-expiry** effect, **not** a signal of *how* the run ended.

| `event` | Extra fields | Meaning |
|---------|--------------|---------|
| `tool.started` | `tool` (e.g. `terminal`), `preview` (e.g. `date`) | Tool invocation begins. |
| `tool.completed` | `tool`, `duration` (float s), `error` (boolean) | Tool finished. `error` is the **result** signal (not lifecycle): a failing command — or a **denied** approval — gives `error: true` yet the run still completes; an **approved** one gives `error: false`. |
| `message.delta` | `delta` (chunk) | Incremental assistant text. |
| `reasoning.available` | `text` (full string) | Reasoning/summary text. |
| `run.completed` | `output` (full string), `usage` | Terminal (success). |
| `run.cancelled` | none beyond `event`/`run_id`/`timestamp` | Terminal, after `stop`. No `output`/`usage`. When stopped before any work, this is the only frame in the replay. |
| `run.failed` | `error` (string) | Terminal, **model/infra error** (reproduced 2026-05-24 via a bad `GOOGLE_API_KEY`), e.g. `error: "Gemini HTTP 400 (INVALID_ARGUMENT): API key not valid…"`. No `output`/`usage`; replays only this single frame. |
| `approval.request` | `command`, `pattern_key`, `pattern_keys[]`, `description`, `choices[]` | Dangerous command gated; run parks at `waiting_for_approval`. |
| `approval.responded` | `choice`, `resolved` | Emitted after an `/approval` response. |

**What makes a run `failed`** (source-derived, `gateway/platforms/api_server.py`):
`failed` is a **model/provider/runtime** failure, not a tool failure. The run task
sets it via two paths with the **identical** wire shape: (a) a *structured* failure
— `run_conversation` returns `{failed: true, error}` for a **non-retryable provider
error** (e.g. a 4xx with no credential-pool/fallback to recover with), and (b) an
**unhandled exception** (`error = str(exc)`). Things that do **not** cause `failed`:
a tool erroring or even `kill -9 $$` (the agent narrates; run still `completed`); a
denied approval (also `completed`); and the agent inactivity timeout
(`agent.gateway_timeout`, default 1800s) — that path lives in the *messaging*
dispatcher, not the `/v1/runs` handler, which calls `run_conversation` directly with
no `wait_for`. Practical repro: point the provider at a bad key (a bad
`GOOGLE_API_KEY` yields the Gemini-400 `error` above), which fails fast at near-zero
token cost.

#### Stop (POST `/v1/runs/{run_id}/stop`)

Cooperative — asks the agent to stop at the next safe interruption point. Against
a live run → `200`:

```json
{ "run_id": "run_bb7e33a7d5624b6cba4ffe34589ccf6d", "status": "stopping" }
```

The run resolves to `status: "cancelled"` (`last_event: "run.cancelled"`); the
cancelled poll response **omits `output` and `usage`**. Against an
already-evicted run → `404 run_not_found` (nested envelope; see Error model).

#### Approval workflow (dangerous-command gating)

Human-in-the-loop gating for dangerous tool commands. **Only fires** when the
profile's `~/.hermes/config.yaml` has `approvals.mode: manual` (not `off`/`smart`),
no `--yolo`/`HERMES_YOLO_MODE`, and a **non-container backend** (containers skip
the checks). The agent must attempt a command matching a dangerous pattern
(`rm -r`, `mkfs`, `dd if=`, `DROP TABLE`, `> /etc/`, `systemctl stop`, `curl | sh`,
…). Verified on `hermes-test` (2026-05-23) with `rm -rf /tmp/…`.

Flow:

1. Run reaches `running`, then on the gated tool parks at **`waiting_for_approval`**
   (`last_event: "approval.request"`). The poll response carries no approval detail
   — it's in the event stream.
2. The events stream emits **`approval.request`**:

   ```json
   {
     "event": "approval.request", "run_id": "run_…", "timestamp": 1779559698.69,
     "command": "rm -rf /tmp/hermes_probe_deny1",
     "pattern_key": "delete in root path",
     "pattern_keys": ["delete in root path"],
     "description": "delete in root path",
     "choices": ["once", "session", "always", "deny"]
   }
   ```

   There is **no approval/request id** — the pending approval is keyed by `run_id`
   (one outstanding per run).
3. Caller responds: **`POST /v1/runs/{run_id}/approval`** with
   `{"choice": "<once|session|always|deny>"}`. Invalid/absent choice → `400`
   `invalid_approval_choice`. Valid → `200`:

   ```json
   { "object": "hermes.run.approval_response", "run_id": "run_…", "choice": "deny", "resolved": 1 }
   ```

   `resolved` = count of pending approvals this call resolved. The body also
   accepts `all`/`resolve_all` (boolean) to resolve all pending approvals at once.
   > ⚠️ `always` writes a **permanent** entry to the profile's `command_allowlist`
   > (config mutation); `session` auto-approves the pattern for the rest of the
   > gateway session. Prefer `once`/`deny` when probing.
4. The stream emits **`approval.responded`** (`choice`, `resolved`), then
   `tool.completed`.

**Outcomes** (the only on-the-wire difference is `tool.completed.error`):

- **Deny:** `tool.completed` `error: true`; the agent narrates the abort
  (`output: "Understood. I have aborted that action."`); run ends **`completed`**
  (not failed).
- **Approve** (verified `choice: "once"`): the tool **executes**; `tool.completed`
  `error: false`; the agent proceeds (`output: "OK."`); run ends `completed`. Full
  sequence: `tool.started` → `approval.request` → `approval.responded` →
  `tool.completed` → `message.delta`/`reasoning.available` → `run.completed`.

(`once`/`deny` exercised; `session`/`always` skipped for their side effects but
accepted as valid.)

**No auto-timeout observed:** despite the docs' `approvals.timeout: 60`, a run sat
`waiting_for_approval` ~89s with no auto-deny. Treat a gated run as blocking
**indefinitely** pending a response.

### Jobs API — `/api/jobs` (scheduled background work)

A CRUD surface for **scheduled/background agent runs** — cron-like recurring
tasks, one-shot deferred tasks, and watchdog scripts. Note the **`/api` prefix,
not `/v1`**. Per the docs the create body "accepts the same shape as `hermes
cron`"; field semantics below were confirmed against `hermes cron create --help`
and live probing (2026-05-24).

> **Not in `/v1/capabilities`.** Unlike the runs endpoints, jobs are **not**
> advertised in the capabilities `endpoints`/`features` (re-checked 2026-05-24).
> Discover them from the docs / this file. Auth: same bearer token. Error
> envelopes: see Error model (jobs business errors are **flat strings**).

Endpoints (all return `{"job": <job>}` unless noted; list returns `{"jobs": […]}`):

- **GET `/api/jobs`** — list. No pagination; an **undocumented `?include_disabled=true|1`**
  query param widens the result (default **excludes** disabled/paused jobs).
- **POST `/api/jobs`** — create. Returns **`200`** (not the runs `202`).
- **GET `/api/jobs/{job_id}`** — fetch definition + last-run state.
- **PATCH `/api/jobs/{job_id}`** — partial update; sent fields merged onto the job.
- **DELETE `/api/jobs/{job_id}`** — remove (also cancels any in-flight run).
  Returns **`{"ok": true}`**, *not* a job entity.
- **POST `/api/jobs/{job_id}/pause`** — pause without deleting (`state:"paused"`,
  `enabled:false`). Idempotent.
- **POST `/api/jobs/{job_id}/resume`** — resume (`next_run_at` recomputed from the
  resume time). Idempotent.
- **POST `/api/jobs/{job_id}/run`** — trigger out of schedule. **Asynchronous:** it
  advances `next_run_at` to "now" for the scheduler's next tick rather than running
  synchronously — `last_run_at`/`last_status`/`repeat.completed` are *not* updated
  by the time it returns (a triggered run took ~20s to land).

#### Create request (POST `/api/jobs`)

Body keys mirror `hermes cron create` flags, but the create handler **forwards
only** `name` (required), `schedule` (required; syntaxes below), `prompt`, `repeat`
(int), `deliver`, and `skills`. **`script` and `no_agent` are silently dropped**
(source-confirmed: the handler never reads them from the body, so they stay at
their defaults — `script: null`, `no_agent: false` — regardless of what is sent).
New jobs start `state:"scheduled"`, `enabled:true`, `repeat.completed:0`, `last_*`
null.

> ⚠️ **`model`, `provider`, `base_url`, `workdir`, `profile`, and `context_from`
> are NOT settable via this API** (verified 2026-05-24): passing them in a create
> *or* PATCH body is **silently ignored** — they stay `null` (no error). The entity
> exposes these slots, but the HTTP API doesn't populate them; they are
> CLI/config-only. A client must not assume a job it creates can carry a per-job
> model/provider override or working directory.
>
> **`deliver` is not validated** at create/patch: a bogus target is stored
> verbatim with `200`; any validation happens at delivery time.

```sh
toys gateway probe POST /api/jobs \
  --body '{"name":"probe","schedule":"every 2h","prompt":"do a thing"}'
```

#### Job entity

Create/get/list/patch/pause/resume/run all return this same object. `id` is **12
lowercase hex chars** (no `run_`-style prefix), e.g. `0ec925dc7192`.

```json
{
  "id": "0ec925dc7192",
  "name": "Hello world",
  "prompt": "Say \"hello world\" in a creative way.",
  "skills": [], "skill": null,
  "model": null, "provider": null, "base_url": null,
  "script": null, "no_agent": false, "context_from": null,
  "schedule": { "kind": "cron", "expr": "0 9 * * *", "display": "0 9 * * *" },
  "schedule_display": "0 9 * * *",
  "repeat": { "times": null, "completed": 2 },
  "enabled": true, "state": "scheduled",
  "paused_at": null, "paused_reason": null,
  "created_at": "2026-05-22T11:51:06.929692-07:00",
  "next_run_at": "2026-05-25T09:00:00-07:00",
  "last_run_at": "2026-05-24T09:00:27.846643-07:00",
  "last_status": "ok", "last_error": null, "last_delivery_error": null,
  "deliver": "local", "origin": null,
  "enabled_toolsets": null, "workdir": null, "profile": null
}
```

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | 12-hex job id. |
| `name` | string | **Required on create.** |
| `prompt` | string\|null | Task instruction. Optional (a `--no-agent` script job needs none). |
| `skills` / `skill` | array / string\|null | Attached skill names (repeatable `--skill`) vs. a separate scalar slot. |
| `model` / `provider` / `base_url` | string\|null | Per-job LLM override. **Read-only via this API** (see create warning). |
| `script` | string\|null | Path under `~/.hermes/scripts/`; its stdout is injected into the prompt each run. |
| `no_agent` | boolean | Skip the LLM — run `script` and deliver stdout verbatim (watchdog pattern). |
| `context_from` | string\|null | Source for run context. **(Unprobed.)** |
| `schedule` | object | Tagged union on `kind` — see below. |
| `schedule_display` | string | Human-readable (mirrors `schedule.display`). |
| `repeat` | object | `{ "times": int\|null, "completed": int }`. `times` = max runs (`null` = unbounded); `completed` increments per run. |
| `enabled` | boolean | `false` while paused. |
| `state` | string | `scheduled` ↔ `paused` (no terminal state — see below). |
| `paused_at` / `paused_reason` | string\|null | Set on pause, cleared on resume; reason `null` for manual pause. |
| `created_at` / `next_run_at` / `last_run_at` | string\|null | **ISO-8601 with offset** (contrast Runs' epoch floats). `last_run_at` null until first run. |
| `last_status` | string\|null | Last run outcome: `"ok"` \| `"error"` \| `null` (before first run). |
| `last_error` / `last_delivery_error` | string\|null | Error detail from last execution / delivery. A failed agent run sets `last_error` to the **exception-prefixed** message, e.g. `"RuntimeError: Gemini HTTP 400 (INVALID_ARGUMENT): API key not valid…"` — note the `RuntimeError:` prefix (contrast a run's bare `error`). `last_delivery_error` stays null when the agent fails before delivery. |
| `deliver` | string | `origin`, `local`, `telegram`, `discord`, `signal`, or `platform:chat_id`. **Defaults to `"local"`.** |
| `origin` | object\|null | Originating channel for `deliver:"origin"`; **always `null` via this API** (set only by chat-platform adapters). Internal shape (not client-observable): `{platform, chat_id, thread_id?}`. |
| `enabled_toolsets` | array\|null | Toolset allowlist; **always `null` via this API** (set only by the in-agent `cronjob` tool). Internal shape: a flat `Array<String>` of toolset names. |
| `workdir` | string\|null | Absolute cwd; injects `AGENTS.md`/`CLAUDE.md`/`.cursorrules`. `null` = none. |
| `profile` | string\|null | Hermes profile; `null` = scheduler's existing profile. |

**PATCH** mutates the full create-able field set (verified: one PATCH changed
`name`, `repeat`, `deliver`, **and** `schedule` together — the new schedule was
re-parsed and `next_run_at` recomputed). The read-only override fields stay ignored.

#### Schedule object (tagged union on `kind`)

The create `schedule` **string** is parsed into one of three stored shapes (the
parser accepts four input syntaxes per the `500` error message):

| `kind` | Stored fields | Created from |
|--------|---------------|--------------|
| `once` | `run_at` (ISO-8601), `display` | a bare **duration** `"30m"`/`"2h"`/`"1d"` (`run_at` = now + duration), **or** an absolute **timestamp** `"2027-02-03T14:00:00"`. One-shot. |
| `interval` | `minutes` (int), `display` | `"every 30m"`/`"every 2h"`. Recurring. |
| `cron` | `expr` (string), `display` | a cron expression `"0 9 * * *"` (`expr` == `display`). Recurring. |

#### Run lifecycle (verified live 2026-05-24)

- `scheduled` — active, waiting for `next_run_at`. `paused` — via `/pause`;
  `/resume` returns it to `scheduled` and recomputes `next_run_at`.
- **No lingering terminal `state` — exhausted jobs are DELETED** (the key client
  implication):
  - A **`once`** job is removed after it fires → `GET` returns `404` and it drops
    off the list. No `completed`/`done` state to observe.
  - A **capped recurring** job (`repeat.times` set) runs `times` times then is
    removed (verified `repeat:2`: survived after run #1 at `completed:1`, deleted
    after run #2).
  - An **uncapped recurring** job (`repeat.times: null`) just increments
    `repeat.completed` and stays `scheduled` with `next_run_at` recomputed.
- A **successful run** sets `last_run_at`, `last_status:"ok"`, leaves
  `last_error`/`last_delivery_error` null, and bumps `repeat.completed`.
- A **failed run** sets `last_status:"error"` and `last_error` (exception-prefixed —
  see the entity table), still bumps `repeat.completed`, and leaves a recurring job
  `state:"scheduled"` (a failed run does **not** disable it).
- **`/run` and the scheduler are asynchronous:** the gateway's in-process scheduler
  picks the job up on a later tick (~20s observed), not instantly. It also **fires
  overdue jobs on startup** (a job whose persisted `next_run_at` was in the past
  ran shortly after the gateway came up, then recomputed its next occurrence).

---

## Behavior notes & limitations

- **System prompts:** frontend system messages/instructions layer atop the core
  agent prompt; tools, memory, and skills are preserved.
- **The `model` field is cosmetic** — the actual LLM is configured server-side.
  Clients may omit it.
- **No file uploads** — inline images only (`image_url` for chat, `input_image`
  for responses).
- **Multi-user:** separate profiles run on separate ports with separate keys; each
  advertises its model id as the profile name.
- **Proxy mode:** another gateway can point `GATEWAY_PROXY_URL` at this server to
  relay messages (split deployments).

## Related documentation (not yet captured)

- Open WebUI integration: `/docs/user-guide/messaging/open-webui`
- Security / approvals: `/docs/user-guide/security`
- Profiles: `/docs/user-guide/profiles`
- Matrix proxy mode: `/docs/user-guide/messaging/matrix#proxy-mode-e2ee-on-macos`
