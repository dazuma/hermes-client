# Design

This document describes the conventions, structure, and public API design for
the `hermes-client` gem — a Ruby client for the
[Hermes Agent API Server](https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server).

The relevant API server documentation is captured locally in
[`hermes-api-server.md`](hermes-api-server.md) so you don't need to re-fetch the
webpage.

It is a living design document. The Hermes API documentation is not exhaustive,
so request/response field details below are **best-effort** and will be refined
as we consult additional docs and experiment against a running server. Until the
gem reaches 1.0, breaking changes to method signatures and object fields are
acceptable as our understanding improves.

## Goals

- A small, idiomatic Ruby client covering the server's HTTP and SSE surface.
- Organized by resource, discoverable, and forgiving of API fields we have not
  yet mapped.
- Minimal dependencies: [`http`](https://github.com/httprb/http) for requests.
  Server-Sent Event streams are parsed in-house (`Stream`) over the same `http`
  connection — no separate SSE dependency. (We evaluated `ld-eventsource` but
  its push/callback model, own connection ownership, and auto-reconnect were a
  poor fit for one-shot request/response streams behind our pull-based
  block-or-enumerator contract; raw SSE framing is ~simple and fully tested.)

## Conventions

### Namespacing and file layout

All classes nest under the `HermesAgent::Client` namespace, mirroring the
existing directory layout (`lib/hermes_agent/client/**/*.rb` maps to
`HermesAgent::Client::*`, which is also what `.yardopts` documents).

```
lib/hermes_agent/client/
  version.rb          # HermesAgent::Client::VERSION
  configuration.rb    # HermesAgent::Client::Configuration
  transport.rb        # HermesAgent::Client::Transport  (HTTP + auth + JSON)
  stream.rb           # HermesAgent::Client::Stream     (SSE, block-or-enumerator)
  entity.rb           # HermesAgent::Client::Entity      (base wrapper)
  errors.rb           # HermesAgent::Client::Error and subclasses
  resources/          # one file per resource group, under Client::Resources
    chat.rb, responses.rb, runs.rb, jobs.rb,
    models.rb, capabilities.rb, health.rb
  entities/           # response wrappers under Client::Entities
    chat_completion.rb, response.rb, run.rb, job.rb, model.rb, ...
```

### Request parameters

- Request parameters are passed as **keyword arguments** using snake_case
  Ruby names, serialized to the JSON field names the server expects.
- Because the field set is not fully known, each request method also accepts an
  open `**extra` (merged into the request body) so callers can pass fields we
  have not yet modeled without waiting on a gem release.
- `model:` is **omitted altogether**. The server ignores it — the actual LLM is
  configured server-side — so the client does not expose a `model:` parameter
  and never sends a `model` field. (Callers who really want to send one can
  still pass it through `**extra`.)

### Return values

- Successful calls return **lightweight wrapper objects** (subclasses of
  `HermesAgent::Client::Entity`, under the `Entities` namespace). Wrappers expose
  method readers for the fields we know about and always provide `#to_h`
  returning the full parsed payload —
  the escape hatch for anything unmapped (and `#[]` for raw key access).
- Field readers are best-effort and may change pre-1.0. The raw hash is the
  source of truth.
- List endpoints return Ruby `Array`s of wrapper objects.

### Naming: resource accessors

The client exposes one accessor per resource group; each returns a resource
object with verb methods. (Chosen over OpenAI's deeper nesting like
`chat.completions.create` for brevity, while staying OpenAI-compatible on the
wire.)

```ruby
client.chat.create(...)
client.responses.create(...)
client.responses.get(id)
client.runs.create(...)
client.jobs.list
```

### Errors

Non-2xx responses raise; network failures raise. The hierarchy:

```
HermesAgent::Client::Error                 (base; rescue this to catch all)
  ConnectionError                          (socket/DNS/TLS failure, no response)
  TimeoutError                             (open/read timeout)
  APIError                                 (received an HTTP error response)
    BadRequestError        (400, 422)
    AuthenticationError    (401)           (missing/invalid bearer token)
    PermissionError        (403)
    NotFoundError          (404)
    RateLimitError         (429)
    ServerError            (>= 500)
```

`APIError` carries `#status`, `#headers`, `#body` (raw) and a parsed
`#error` hash when the server returns a structured error.

#### Observed error response shape

Probed against the `hermes-test` profile (`toys gateway probe` with bad
tokens / malformed bodies / bad paths). There are **two distinct error
families**, and the client must tolerate both:

- **Application-level errors** (auth failure, body validation, missing
  resource) return **OpenAI-style JSON**: `{ "error": { "message", "type",
  "param"?, "code"? } }`. Examples observed:
  - `401` bad/empty token → `{message: "Invalid API key", type:
    "invalid_request_error", code: "invalid_api_key"}`
  - `400` empty `/v1/responses` body → `{message: "Missing 'input' field",
    type: "invalid_request_error", param: null, code: null}`
  - `400` wrong `input` type → `{message: "'input' must be a string or
    array", ...}`; `400` malformed JSON → `{message: "Invalid JSON in request
    body", type: "invalid_request_error"}` (no `param`/`code` keys at all)
  - `400` empty `/v1/chat/completions` body → `{message: "Missing or invalid
    'messages' field", type: "invalid_request_error"}`
  - `404` on a real route with a bad id (`GET /v1/responses/{bad}`) →
    `{message: "Response not found: ...", type: "invalid_request_error"}`
- **Framework/router-level errors** return **bare text, not JSON**:
  - `404` on an unrouted path → `404: Not Found`
  - `405` wrong method on a real route → `405: Method Not Allowed`

Implications for the implementation:
- `APIError#error` parsing must **not assume JSON** — the router-level 404/405
  bodies are plain text, so parse defensively and fall back to `#body`.
- Within the structured family the field set is **inconsistent**: `message`
  and `type` are always present, but `param` and `code` may be `null` or
  omitted entirely. Treat them as best-effort readers.
- `type` is **not** a reliable discriminator — it was `invalid_request_error`
  for every case including `401`. Map HTTP **status** to the error subclass
  (as the hierarchy already does); do not key off `type`/`code`.

### Streaming

Streaming is exposed through **separate methods**, not a `stream:` flag. Any
method that streams is named with a `stream_` prefix — both streaming
counterparts of a non-streaming verb (`create` → `stream_create`) and
inherently streaming endpoints with no non-streaming sibling
(`runs.stream_events`). The prefix is a general marker that a method returns a
stream, which keeps every method's return type unambiguous from its name:
non-streaming methods always return a result object, streaming methods always
return/yield a stream.

The streaming methods follow a **block-or-enumerator** pattern, implemented once
in `Stream`:

- With a block, it yields each parsed event as it arrives (natural backpressure)
  and returns the final aggregated object when the stream closes.
- Without a block, it returns a `Stream` (an `Enumerable`) the caller iterates.
  After the stream closes, the final aggregated result object can be obtained
  from the stream.

```ruby
# block form
client.chat.stream_create(messages: msgs) do |event|
  print event.delta
end

# enumerator form
stream = client.chat.stream_create(messages: msgs)
stream.each { |event| print event.delta }
```

Events are wrapper objects too. Chat streaming surfaces the server's custom
`hermes.tool.progress` events as a distinct event type (separate from text
deltas) so tool activity does not pollute assistant text.

### Observed streaming event types

Captured by probing the `hermes-test` profile (`toys gateway chat/respond
--stream`); refine as we see more cases:

- **Chat completions** stream OpenAI-style: **unnamed** SSE frames (no `event:`
  line) whose `data:` is a `chat.completion.chunk` object. The first chunk
  carries `delta.role`, subsequent chunks carry `delta.content`, and the final
  chunk has an empty `delta`, `finish_reason: "stop"`, and a `usage` block. The
  stream terminates with a literal `data: [DONE]` sentinel. All chunks (and the
  tool-progress frames below) share a single stable `id` for the whole stream.
  - **`hermes.tool.progress`** events (captured by prompting `hermes-test` to
    "list the files in my current directory", which made the server agent
    autonomously run tools) are the one **named** frame in the chat stream:
    `event: hermes.tool.progress` with a `data:` payload that — unlike the
    Responses API's named events — has **no `type` field and no
    `sequence_number`**. They are **interleaved** between the role chunk and
    the content chunks (tools run before the assistant text is produced). Each
    tool call emits **two** events keyed by a `toolCallId` (`call_…`): a
    `status: "running"` event carrying `{ tool, emoji, label, toolCallId,
    status }` and a `status: "completed"` event carrying only `{ tool,
    toolCallId, status }` (no `emoji`/`label`). `tool` is the tool name (e.g.
    `search_files`, `terminal`); `label` is a short human-facing descriptor of
    the invocation (e.g. the search glob `*`, or the command `ls -F`). A single
    turn can run **multiple** tools (the observed turn ran `search_files` then
    `terminal`, four frames total). `status` appears to be a pure **lifecycle**
    marker (tool started / tool finished executing), **not** a success/failure
    signal: probing three deliberate failure modes — `read_file` on a
    nonexistent path, and `terminal`/`sqlite3` against a permission-protected
    file — every call still reported `running` → `completed`. Tool *failures*
    are surfaced as the tool's result content (which the model then narrates),
    not as a distinct progress status; no `error`/`failed` status was
    observed. (A framework-level refusal or a timeout might still produce
    another status — untested.) These frames are **not**
    `chat.completion.chunk` objects (no `choices`/`delta`), so the streaming
    layer must route them to a distinct event type and keep them out of the
    `ChatCompletion.from_chunks` delta aggregation.
- **Responses API** streams **named** events; each `data:` payload repeats the
  name in a `type` field and carries a monotonic `sequence_number` (0-based).
  Full observed order for a simple text turn: `response.created` (seq 0) →
  `response.output_item.added` (seq 1) → `response.output_text.delta` (seq 2,
  one per delta) → `response.output_text.done` (seq 3) →
  `response.output_item.done` (seq 4) → **`response.completed`** (seq 5, the
  terminal event). There is no `response.done` and **no `[DONE]` sentinel** —
  the stream simply ends after `response.completed` (unlike chat completions,
  which do terminate with `data: [DONE]`).
  - `response.created` carries the `response.id` (`resp_…`) used for
    `previous_response_id` chaining, plus `status: "in_progress"`, `model`,
    `created_at`, and an empty `output: []`.
  - The delta events thread an `item_id` (`msg_…`), `output_index`, and
    `content_index`; `response.output_text.delta` carries the incremental
    `delta` string while `response.output_text.done` carries the assembled
    `text`. (Both also carry a `logprobs` array, empty in the observed turn.)
  - The `response.output_item.added` / `response.output_item.done` events nest
    the output item under an **`item`** key (`{ id, type, status, role,
    content }`) alongside `output_index` — not under `response`. `added` has
    `status: "in_progress"` with empty `content`; `done` has `status:
    "completed"` with the assembled `content`. `ResponseStreamEvent#item`
    wraps it as a `ResponseOutputItem`; `#response` wraps the `response` key
    present only on `response.created`/`response.completed`.
  - **`response.completed` carries the full final `response` object** —
    `status: "completed"`, the complete `output` array (message items with
    `content: [{type: "output_text", text}]`), and a `usage` block using
    Responses-API field names `{ input_tokens, output_tokens, total_tokens }`
    (note: *not* chat's `prompt_tokens`/`completion_tokens`). The `Stream`
    aggregator can therefore take the final `Response` straight from this
    event rather than reconstructing it from deltas.
  - A **tool-executing turn** (captured with the same "list the files in my
    current directory" prompt) uses the **same** `response.output_item.added` /
    `.done` events — there are **no `hermes.tool.progress` frames** (that custom
    event is chat-completions-only) and **no separate function-call event
    types**. Each tool call and its result are ordinary output items, each with
    its own `output_index`, in sequence: a `function_call` item (`{ id: fc_…,
    type, status, name, call_id, arguments }`), then a `function_call_output`
    item (`{ id: fco_…, type, call_id, status, output: [{ type: "input_text",
    text }] }`), repeated per tool, then the final `message` item — all also
    echoed in `response.completed`'s `output` array. Notable details: the
    `arguments` JSON string is delivered **whole** in the `added` event (no
    `response.function_call_arguments.delta` streaming); `function_call_output`'s
    `output` is an **array of content parts** (each a `{ type: "input_text",
    text }` whose `text` is itself a JSON string), which differs from the raw
    JSON-string `output` recorded for the non-streaming GET shape below — worth
    reconciling. As with chat, `status` is lifecycle-only: `search_files` here
    *timed out* (`"[Command timed out after 60s]"`) yet its item still reported
    `status: "completed"`, and the model recovered by calling `terminal`.

## Client construction and configuration

```ruby
client = HermesAgent::Client.new(
  base_url:   "http://127.0.0.1:8642",  # default; host root, not including /v1
  api_key:    ENV["HERMES_API_KEY"],    # default source for the bearer token
  timeout:    nil,                       # read timeout (seconds)
  open_timeout: nil,
)
```

`Configuration` holds these and is also settable via a block:

```ruby
client = HermesAgent::Client.new do |config|
  config.base_url = "https://hermes.example.com"
  config.api_key  = "..."
end
```

Notes:
- `base_url` is the server root; resources own their path prefixes
  (`/v1/...`, `/api/jobs`, `/health`) since they are not uniform.
- The bearer token is sent as `Authorization: Bearer <api_key>` on every
  request. Default client-side env var is **`HERMES_API_KEY`** (distinct from
  the server's own `API_SERVER_KEY`). *(Env var name: decision to confirm.)*
- Mutating requests accept an optional `idempotency_key:` sent as the
  `Idempotency-Key` header (server dedupes within ~5 minutes).
- The server advertises **session-continuity headers** in `/v1/capabilities`:
  `X-Hermes-Session-Id` (`session_continuity_header`) and `X-Hermes-Session-Key`
  (`session_key_header`). These appear to be the mechanism for carrying
  continuity on the otherwise-stateless chat endpoint; exact usage to confirm.

## Resource API

Method signatures below are the intended high-level surface; exact body/field
lists are filled in as we map them. `**extra` is omitted for brevity but
present on every request method.

### `client.chat` — Chat Completions (`POST /v1/chat/completions`, stateless)

```ruby
client.chat.create(messages:)                 # => ChatCompletion
client.chat.stream_create(messages:, &block)  # streams ChatCompletionChunk /
                                              #   ToolProgress events
```

- `messages` is the OpenAI-style array; content may include `image_url` parts
  (http(s) or `data:` URIs) for inline images.
- OpenAI-compatible on the wire; additional sampling params flow through.
- No `model` field is sent (server configures the model; it ignores a
  client-supplied one). Callers can still pass one via `**extra`.
- Observed (probed against `hermes-test`) non-streaming response: `{ id:
  "chatcmpl-…", object: "chat.completion", created, model, choices: [{ index,
  message: { role, content }, finish_reason }], usage: { prompt_tokens,
  completion_tokens, total_tokens } }`. `ChatCompletion`/`ChatChoice`/
  `ChatMessage`/`ChatUsage` mirror this.
- Streaming (`stream_create`, body `stream: true`): unnamed `data:` frames each
  a `chat.completion.chunk` (see "Observed streaming event types"), terminated
  by `data: [DONE]`. No final aggregate is sent, so `ChatCompletion.from_chunks`
  reconstructs one from the deltas.

### `client.responses` — Responses API (`/v1/responses`, server-side state)

```ruby
client.responses.create(input:,
                        previous_response_id: nil,  # chain a prior turn
                        conversation: nil)           # named conversation
                                                     #   => Response
client.responses.stream_create(input:, previous_response_id: nil,
                              conversation: nil, &block)  # streams Response events
client.responses.get(id)      # GET    /v1/responses/{id}  => Response
client.responses.delete(id)   # DELETE /v1/responses/{id}  => deletion result
```

- Server persists conversation state; chain multi-turn either by passing the
  prior `previous_response_id` or a stable `conversation` name.
- Inline images supplied as `input_image` input parts.
- Storage is capped server-side (~100 responses, LRU eviction) — callers should
  not assume older responses remain retrievable.
- No `model` field is sent (server configures the model). `previous_response_id`
  / `conversation` are omitted from the body when nil. Callers can pass
  unmodeled fields via `**extra`.
- Observed (probed against `hermes-test`) non-streaming response (`POST` and
  `GET` return the same object): `{ id: "resp_…", object: "response", status:
  "completed", created_at, model, output: [...], usage: { input_tokens,
  output_tokens, total_tokens } }` — note Responses-API usage field names, not
  chat's `prompt_tokens`/`completion_tokens`. `Response`/`ResponseOutputItem`/
  `ResponseContent`/`ResponseUsage` mirror this.
  - `output` is a **heterogeneous array**. A plain turn has a single `message`
    item (`{ type: "message", role: "assistant", content: [{ type:
    "output_text", text }] }`). A turn that runs tools (observed via a named
    `conversation` triggering the server's `memory` tool) interleaves
    `function_call` items (`{ type, name, arguments (raw JSON string), call_id }`)
    and `function_call_output` items (`{ type, call_id, output (raw JSON
    string) }`) before the final `message`. `Response#output_text` aggregates
    only the `message` items' text.
  - Chaining: passing `previous_response_id` carries context (verified — a
    follow-up arithmetic turn produced the correct sum), but the chained
    response does **not** echo `previous_response_id` in its body.
- `DELETE /v1/responses/{id}` returns `{ id, object: "response", deleted: true }`
  (modeled by `ResponseDeletion`); a subsequent `GET` of that id returns the
  `404 "Response not found: …"` documented under the error section.
- Streaming (`stream_create`, body `stream: true`): named SSE events (see
  "Observed streaming event types"); the assembled `Response` is taken straight
  from the terminal `response.completed` event by `Response.from_events` (no
  reconstruction from deltas needed, and no `[DONE]` sentinel).

### `client.runs` — Runs API (long-running agent runs)

```ruby
client.runs.create(...)            # POST /v1/runs              => Run (has #id / run_id)
client.runs.get(run_id)            # GET  /v1/runs/{id}         => Run (poll state)
client.runs.stream_events(run_id, &block) # GET /v1/runs/{id}/events => SSE stream
client.runs.stop(run_id)           # POST /v1/runs/{id}/stop    => Run/result
```

- `stream_events` uses the same block-or-enumerator streaming pattern over the
  SSE endpoint, yielding run-progress events.
- `/v1/capabilities` advertises these run routes: `POST /v1/runs`,
  `GET /v1/runs/{run_id}`, `GET /v1/runs/{run_id}/events`,
  `POST /v1/runs/{run_id}/stop`, and additionally
  `POST /v1/runs/{run_id}/approval` (paired with an `approval_events` feature) —
  a human-in-the-loop approval flow we have not yet modeled.

### `client.jobs` — Jobs API (scheduled background work, under `/api/jobs`)

```ruby
client.jobs.list                  # GET    /api/jobs               => [Job]
client.jobs.create(...)           # POST   /api/jobs               => Job
client.jobs.get(job_id)           # GET    /api/jobs/{id}          => Job
client.jobs.update(job_id, ...)   # PATCH  /api/jobs/{id}          => Job
client.jobs.delete(job_id)        # DELETE /api/jobs/{id}
client.jobs.pause(job_id)         # POST   /api/jobs/{id}/pause
client.jobs.resume(job_id)        # POST   /api/jobs/{id}/resume
client.jobs.run(job_id)           # POST   /api/jobs/{id}/run      (run now)
```

- Note these live under `/api/jobs`, not `/v1` — `Jobs` carries its own prefix.
- The Jobs endpoints were **not** present in the `hermes-test`
  `/v1/capabilities` advertisement, so they may be gated, versioned separately,
  or absent in some builds — confirm against a server that exposes them.

### `client.models` / `client.capabilities` — discovery (`/v1`)

```ruby
client.models.list      # GET /v1/models        => [Model]
client.capabilities.get # GET /v1/capabilities   => Capabilities
                        #   (chat_completions, responses_api, run_submission, ...)
```

Observed (probing the `hermes-test` profile via `toys gateway`; refine as we
see more), `GET /v1/capabilities` returns an object with
`object: "hermes.api_server.capabilities"` and these top-level keys:

- `platform` — the platform identifier, e.g. `"hermes-agent"`.
- `model` — the configured server-side model id, e.g. `"hermes-test"`.
- `auth` — `{ "type": "bearer", "required": true }`.
- `runtime` — the execution model, e.g. `mode: "server_agent"`,
  `tool_execution: "server"`, `split_runtime: false`, plus a human-readable
  `description` string.
- `features` — a boolean matrix: `chat_completions`/`chat_completions_streaming`,
  `responses_api`/`responses_streaming`, `run_submission`, `run_status`,
  `run_events_sse`, `run_stop`, `run_approval_response`, `tool_progress_events`,
  `approval_events`, `cors`, plus the session-header names (see below).
- `endpoints` — a map of logical name → `{ method, path }`: the server's own
  advertisement of its routes (see the `runs`/jobs notes above).

`GET /v1/models` returns the OpenAI list shape: `{ object: "list", data: [ {
id, object: "model", created, owned_by, permission, root, parent } ] }`.
`GET /health` returns `{ "status": "ok", "platform": "hermes-agent" }`.

### `client.health` — health (root paths, no `/v1`)

```ruby
client.health.check     # GET /health           => Health  (#status == "ok")
client.health.detailed  # GET /health/detailed   => HealthDetails
```

Observed (probing `hermes-test`): `/health/detailed` is a **superset** of
`/health` — same `status` and `platform`, plus `gateway_state` (e.g.
`"running"`), `platforms` (a map keyed by platform name, e.g. `api_server`,
each `{ state, error_code, error_message, updated_at }`), `active_agents` (an
integer count), `exit_reason` (nullable), and incidental `updated_at` / `pid`.
(The earlier guess of "sessions / resource usage" was not borne out.)
`HealthDetails` is an independent `Entity` (not a `Health` subclass) with a
reader for every observed field: `status`, `platform`, `gateway_state`,
`platforms`, `active_agents`, `exit_reason`, `updated_at`, and `pid`. The
`platforms` reader returns a `Hash` keyed by platform name whose values are
`PlatformStatus` entities (`state`, `error_code`, `error_message`,
`updated_at`) rather than raw hashes.

## Internal layering

- **`Transport`** is the single chokepoint for HTTP: it owns the `http` gem
  connection, attaches the `Authorization` (and optional `Idempotency-Key`)
  headers, serializes/parses JSON, maps status codes to the error hierarchy,
  and exposes `get` / `post` / `delete` (`patch` to come). It also opens SSE
  streams via `stream_post` — checking the response status up front (so errors
  raise before any streaming) and handing the live response body to `Stream`
  wrapped (`map_stream_errors`) so that a connection/read failure encountered
  *mid-stream* (the body is read lazily, after the request returns) is mapped
  to `TimeoutError`/`ConnectionError`, the same as on a non-streaming request,
  rather than leaking the raw `http`-gem exception. This keeps `Stream`
  HTTP-agnostic: it only ever sees mapped errors.
- **Resource objects** are thin: they build paths and params and delegate to
  `Transport`, wrapping results in the appropriate `Entity` subclass.
- **`Stream`** consumes the response body's byte chunks, parses SSE frames
  in-house (no external SSE library), wraps each frame's `data` payload in an
  event wrapper, and implements the block-or-enumerator contract. It is
  single-pass and HTTP-agnostic (it consumes anything yielding String chunks
  via `#each`), and builds the final aggregated object via an injected
  aggregator — for chat, `ChatCompletion.from_chunks` (the chat stream sends no
  final aggregate object, so it is reconstructed from the deltas).
- **`Entity`** is the wrapper base (method readers + `#to_h` + `#[]`).

This keeps auth, error mapping, and JSON handling in one place and makes the
resource classes trivial to add as we map more of the API.

## Open questions / to confirm

These need additional docs or experimentation against a live server. The
`toys gateway` tools (start a local gateway, then probe endpoints and dump
prettified JSON / raw SSE frames) are the means to resolve these against a
running server; several below have been refined that way already.

- Exact request bodies and response field names for each endpoint. Discovery,
  chat completions, and the Responses API (create/get/delete/stream, including
  the non-streaming, deletion, and tool-item output shapes) are now mapped (see
  above); `runs` and `jobs` request/response bodies are still largely unknown.
- The full set of SSE event types and payloads. Chat-completion chunks
  (including the custom `hermes.tool.progress` frames) and the full Responses
  API event sequence — including the terminal `response.completed` — are now
  captured (above); still outstanding is the run events stream.
- Whether list endpoints (`jobs`, `models`) paginate or always return full
  arrays. (`models` was observed returning a full `{ object: "list", data }`
  with no pagination fields.)
- ~~Structured error response shape (for `APIError#error`).~~ Captured above:
  two families (OpenAI-style `{error: {...}}` for app-level errors, bare text
  for router-level 404/405). Remaining unknown: the `>= 500` ServerError body
  shape (hard to provoke safely on a live server).
- Final name of the client-side API-key environment variable.
- Whether a convenience helper for `conversation` chaining is worth adding.
- Retry/backoff policy (none planned for v1 unless the server signals retryable
  conditions).

Known limitations in the current streaming implementation (deferred, revisit):

- **Chat stream aggregation assumes a single choice.**
  `ChatCompletion.from_chunks` reconstructs only `choices[0]` (it concatenates
  every chunk's `delta.content` into one message). A multi-choice stream
  (`n > 1`) would need the chunks grouped by `choices[].index` before
  assembling one message per choice. Not yet handled — confirm whether the
  server ever emits `n > 1` and, if so, generalize the aggregator.

Resolved (were known limitations):

- **Mid-stream connection/read failures are now mapped.** A socket/timeout
  failure during stream iteration is translated to
  `TimeoutError`/`ConnectionError` by `Transport#map_stream_errors` (see
  Internal layering), not the raw `http`-gem exception. Behavior is
  map-and-raise: chunks delivered before the failure stand, and no partial
  aggregate is produced (partial-result recovery was considered and declined
  for v1).
- **Malformed JSON is now mapped — uniformly.** A body the client expected to
  be JSON but cannot parse raises `MalformedResponseError` (a direct `Error`
  subclass, *not* an `APIError` — the HTTP request itself succeeded; it carries
  the unparseable text as `#body` and the `JSON::ParserError` as `#cause`)
  rather than leaking a raw `JSON::ParserError`. The single chokepoint is
  `Util.parse_json`, used by both `Transport#handle` (non-streaming) and
  `Stream#dispatch` (a malformed SSE frame), so the two paths behave alike.
  Note this is for bodies expected to be JSON; a non-JSON *error* body is still
  deliberately tolerated by `APIError.parse_error_payload` (falling back to raw
  text, for the server's router-level bare-text 404/405s).
