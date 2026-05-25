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
- A few readers are sourced from **response headers**, not the JSON body: the
  `Entities::SessionHeaders` mixin (included by `ChatCompletion` and `Response`)
  adds `#session_id` / `#session_key` from the session-continuity headers. They
  are stored outside the wrapped payload, so `#to_h` / `#[]` still reflect only
  the body, but they do participate in `#==` / `#hash`. Internally, `Transport`
  surfaces them: `#post` / `#stream_post` return a `Transport::Result`
  (`body` + downcased-key `headers`), while the header-agnostic `#get` / `#delete`
  return the bare parsed body.

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

The server emits **three** error-envelope shapes (nested OpenAI-style JSON; a
flat `{error: "<string>"}` for jobs business errors; bare text for router-level
404/405) — full catalog and examples in
[`hermes-api-server.md`](hermes-api-server.md) under "Error model". What that
means for the client:

- **Map HTTP status to the subclass**, never `type`/`code`. `type` is
  `invalid_request_error` for nearly everything (including `401`), so it is not a
  discriminator; the hierarchy above keys off status alone.
- **`APIError#error` parsing must not assume JSON.** Parse defensively and fall
  back to `#body` for the bare-text router errors, and accept **either** a nested
  `error.message` **or** a flat string `error` (jobs). This lives in
  `APIError.parse_error_payload`.
- **Structured fields are best-effort:** `message`/`type` are usually present but
  `param`/`code` may be `null` or omitted — treat the readers accordingly.
- A bad jobs `schedule` is a **`500`** that is really invalid input, so the
  `>= 500` → `ServerError` body is at least partly user-caused (documented on the
  jobs methods so callers aren't surprised).

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

#### Event wrapping & aggregation

The three streams frame events differently (full frame shapes, event sequences,
and field lists in [`hermes-api-server.md`](hermes-api-server.md) under each
endpoint's streaming notes). `Stream` is told how to **classify** and how to
**aggregate** per endpoint:

- **Classification** — `Stream`'s `event_class:` is either a single `Entity`
  subclass (wrapping every frame) or a **callable that picks the class from the
  frame's SSE `event:` name**:
  - **Chat** uses the callable: the one named frame (`event: hermes.tool.progress`)
    routes to **`ChatToolProgress`**, everything else (the unnamed
    `chat.completion.chunk` frames) to **`ChatCompletionChunk`**. Both are still
    yielded to the caller's block, so tool activity is visible but kept out of the
    text aggregation.
  - **Responses** passes a **single class** (`ResponseStreamEvent`) since its event
    identity is carried in-payload as `type`, not on an SSE `event:` line.
    `ResponseStreamEvent#item` wraps the per-item `item` key as a
    `ResponseOutputItem`; `#response` wraps the `response` key present only on
    `response.created`/`response.completed`.
  - **Runs** passes a single class (`RunEvent`) keyed off the in-payload `event`
    string.
- **Aggregation** — the injected aggregator builds the final return object:
  - **Chat** sends no final aggregate object, so **`ChatCompletion.from_chunks`**
    reconstructs one from the deltas (and ignores the non-chunk tool-progress
    frames). See the single-choice note in the chat resource section.
  - **Responses** emits the full final object on the terminal `response.completed`,
    so **`Response.from_events`** takes it straight from that event — no delta
    reconstruction, and there is no `[DONE]` sentinel to watch for.
- **`ResponseOutputItem` tolerates representation drift** (the server returns the
  same logical item two ways — see the wire doc's "representation differences"):
  - `#output` may be an **Array** of content parts (streaming) or a **raw JSON
    String** (non-streaming POST/GET); the reader passes the raw value through and
    `#output_text` normalizes to the string.
  - `#id`/`#status` are populated only for items seen via **per-item streaming
    events**; they are `nil` for items read off a final `Response#output` (the
    server omits them there).

## Client construction and configuration

```ruby
client = HermesAgent::Client.new(
  base_url:   "http://127.0.0.1:8642",  # default; host root, not including /v1
  api_key:    ENV["HERMES_API_KEY"],    # default source for the bearer token
  timeout:    nil,                       # read timeout (seconds)
  open_timeout: nil,
  keep_alive_timeout: 5,                 # persistent-connection idle reuse window (seconds)
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
- **Persistent connection.** `Transport` holds a single keep-alive
  `HTTP::Session` (the `http` gem's `HTTP.persistent`), scoped to the transport
  instance, so the TCP/TLS handshake happens once and the connection is reused
  across requests. The `http` gem transparently reopens it when it has been
  closed by the server, has been idle past the keep-alive window, or a prior
  request failed. `keep_alive_timeout:` (seconds; default `5`) tunes that idle
  reuse window — it is passed as `HTTP.persistent`'s `timeout:`, **not** a
  request timeout (those are `timeout:`/`open_timeout:`). Because the session
  holds live connection state, the transport — and the `Client` — is **not
  thread-safe**; use one client per thread.
- The bearer token is sent as `Authorization: Bearer <api_key>` on every
  request. Default client-side env var is **`HERMES_API_KEY`** (distinct from
  the server's own `API_SERVER_KEY`).
- An optional `idempotency_key:` is sent as the `Idempotency-Key` header. The
  server honors it on **only** the **non-streaming** `chat.create` and
  `responses.create` paths (verified 2026-05-25 — see `hermes-api-server.md`);
  it is **ignored** on the streaming variants, all of `runs`, and all `jobs`
  mutations, so the client **does not** accept the kwarg there (offering it
  would imply a dedup that does not happen). Dedup window is ~5 minutes
  (TTL 300 s). **No replay is observable to the caller** — a cached hit returns
  the same status/body content with a *freshly regenerated* `id`/`created`, and
  no replay header — so the client cannot (and does not) surface a
  "was-deduplicated" signal; there is nothing to surface.
- The server advertises **session-continuity headers** in `/v1/capabilities`:
  `X-Hermes-Session-ID` (`session_continuity_header`) and `X-Hermes-Session-Key`
  (`session_key_header`). Observed behavior (probed against `hermes-test`):
  - `POST /v1/chat/completions` **accepts** both as request headers (each
    optional and independent); the client surfaces them as `session_id:` /
    `session_key:` on `chat.create` / `chat.stream_create`.
  - `POST /v1/responses` does **not** honor them on the request (no effect), so
    the client does not send them there.
  - **Both** POST endpoints **return** the headers on the response (including on
    SSE responses). `X-Hermes-Session-ID` is always present (the server
    generates one when the request supplied none); `X-Hermes-Session-Key` comes
    back only when one was sent. `GET /v1/responses/{id}` returns **neither**.
  - The client reads these response headers onto the returned entity (see
    "Return values" below); they come from headers, not the JSON body.

## Resource API

Method signatures below are the intended high-level surface; exact body/field
lists are filled in as we map them. `**extra` is omitted for brevity but
present on every request method.

### `client.chat` — Chat Completions (`POST /v1/chat/completions`, stateless)

```ruby
client.chat.create(messages:, session_id:, session_key:,
                   idempotency_key:)                            # => ChatCompletion
client.chat.stream_create(messages:, session_id:, session_key:, &block)
                                              # streams ChatCompletionChunk /
                                              #   ToolProgress events
                                              #   (no idempotency_key: ignored on streams)
```

- `messages` is the OpenAI-style array; content may include `image_url` parts for
  inline images.
- `session_id:` / `session_key:` are optional; when given they are sent as the
  `X-Hermes-Session-ID` / `X-Hermes-Session-Key` request headers — chat is the
  only endpoint that honors them on the request
  ([`hermes-api-server.md`](hermes-api-server.md) → Session & memory headers). The
  returned `ChatCompletion` exposes the server's `#session_id` / `#session_key`
  from the **response** headers regardless of whether they were sent.
- `idempotency_key:` (optional, `create` only) → the `Idempotency-Key` header.
  The replay is **transparent** (nothing to surface — see Return values). Not
  offered on `stream_create` (the server ignores it on streams).
- No `model` field is sent (server-configured); callers can pass one (or extra
  sampling params) via `**extra`. The server **ignores OpenAI `n`** and always
  returns a single `choices[0]`, so the client models one choice (see Known
  limitations).
- Response is modeled by `ChatCompletion` / `ChatChoice` / `ChatMessage` /
  `ChatUsage`. Streaming has no final aggregate, so `ChatCompletion.from_chunks`
  reconstructs one from the `ChatCompletionChunk` deltas (see Event wrapping).
  Wire shapes: [`hermes-api-server.md`](hermes-api-server.md) → Chat Completions.

### `client.responses` — Responses API (`/v1/responses`, server-side state)

```ruby
client.responses.create(input:,
                        previous_response_id: nil,  # chain a prior turn
                        conversation: nil,           # named conversation
                        idempotency_key: nil)        # dedup retries (~5 min)
                                                     #   => Response
client.responses.stream_create(input:, previous_response_id: nil,
                              conversation: nil, &block)  # streams Response events
                                                          #   (no idempotency_key: ignored on streams)
client.responses.get(id)      # GET    /v1/responses/{id}  => Response
client.responses.delete(id)   # DELETE /v1/responses/{id}  => deletion result

client.responses.conversation                          # => Conversation (id-tracking)
client.responses.conversation(name: "thread-1")        # => Conversation (named, server-side)
client.responses.conversation(previous_response_id: id) # resume an id-tracked thread
```

- **`conversation`** returns a stateful `Conversation` helper that auto-chains
  multi-turn dialogue so each turn takes only `input:`. Two mutually exclusive
  modes (selected at construction): **id-tracking** (default) remembers each
  turn's response id client-side and threads it as `previous_response_id` into
  the next turn (seedable via `previous_response_id:` to resume across process
  restarts); **named** (`name:`) sends a stable `conversation` name each turn
  and lets the server keep the thread. `#create` / `#stream_create` mirror the
  resource methods (same return entities, same block-or-enumerator stream
  contract) and `#last_response_id` is recorded in both modes.
  - **Streaming id-capture design:** the new turn's id is only known once the
    terminal `response.completed` arrives, so `Conversation#stream_create`
    captures it by folding a callback **into the stream's aggregator** (via the
    doc-private `Responses#stream_response(on_result:)` seam), not via a public
    settable hook on the returned `Stream`. This makes capture fire exactly when
    the result is built — identically for the block and enumerator forms — and
    leaves nothing public for a caller to clobber (a single-slot public hook
    would be last-writer-wins; even append-only would add public surface for one
    internal caller). `Stream` and `stream_create`'s public signature are
    unchanged.
  - Not thread-safe: a `Conversation` is one sequential thread; issue and (for
    streaming) consume each turn before the next.

- Chain multi-turn either by passing the prior `previous_response_id` or a stable
  `conversation` name; both are omitted from the body when nil. Inline images go
  in as `input_image` input parts. No `model` is sent; `**extra` carries unmodeled
  fields.
- **No `session_id:` / `session_key:` params** — this endpoint does not honor those
  request headers. The `Response` from `create`/`stream_create` still exposes the
  server-generated `#session_id` (from the response header); `responses.get`
  returns no session header, so its `#session_id` is `nil`.
- `idempotency_key:` (optional, `create` only) behaves as on chat — transparent
  replay, not offered on `stream_create`.
- **Entities:** `Response` / `ResponseOutputItem` / `ResponseContent` /
  `ResponseUsage` (`ResponseDeletion` for `delete`). `Response#output` is a
  heterogeneous array (a `message` item, optionally preceded by `function_call` /
  `function_call_output` items for tool turns); `#output_text` aggregates only the
  `message` items' text. `ResponseOutputItem` tolerates the streaming-vs-fetched
  representation drift (see Event wrapping). The assembled `Response` from a stream
  comes straight from the terminal `response.completed` via `Response.from_events`.
  Wire shapes, the `store`/`truncation`/`conversation_history` request fields, the
  ~100-response storage cap, and the delete/404 behavior:
  [`hermes-api-server.md`](hermes-api-server.md) → Responses API.

### `client.runs` — Runs API (long-running agent runs)

```ruby
client.runs.create(input:,                    # POST /v1/runs            => Run
                   instructions: nil,          #   system directive (honored)
                   conversation_history: nil,  #   prior turns (OpenAI message array)
                   previous_response_id: nil,  #   chain a stored /v1/responses turn
                   session_id: nil)            #   correlation label (see note)
client.runs.get(run_id)                        # GET  /v1/runs/{id}       => Run (poll)
client.runs.stream_events(run_id, &block)      # GET  /v1/runs/{id}/events (SSE)
client.runs.stop(run_id)                       # POST /v1/runs/{id}/stop  => stop ack
client.runs.respond_approval(run_id, choice:)  # POST /v1/runs/{id}/approval
```

Unlike chat/responses, a run is **server-side asynchronous**: `create` returns
immediately (`202`) with only `{ run_id, status: "started" }`, and progress is
tracked by polling `get` or subscribing to `stream_events`. (Create-body
semantics, the status lifecycle, the failed-run analysis, retention/eviction, and
the full approval-flow wire shapes are in
[`hermes-api-server.md`](hermes-api-server.md) → Runs API.)

- **Create params** the client exposes: `input:` (required), `instructions:`,
  `conversation_history:` (OpenAI message array), `previous_response_id:`, and
  `session_id:` (a correlation label, not inline context). No `model:` param —
  the server accepts one but ignores it (always the gateway-configured model), so
  it is only reachable via `**extra`.
- **`Run`** is returned by both `create` and `get` (`#id` aliases `#run_id`).
  `create`'s minimal Run carries only `run_id` + `status`. **`output` and `usage`
  are nullable** — present on a `completed` run, **absent when `cancelled`/`failed`**
  and before terminal — so readers must tolerate `nil`; a `failed` run adds an
  `error` string. Entity files hold `Run` plus `RunUsage`/`RunEvent`/etc.
- **`stop`** returns a small ack (`{ run_id, status: "stopping" }`); modeled as a
  plain ack, not a `Run`.
- **`stream_events`** is block-or-enumerator over `RunEvent` (the `event`-keyed
  frames; see Event wrapping). Replay works for an already-terminal run only
  during the retention window.
- **`respond_approval(run_id, choice:)`** answers a gated dangerous-command
  request. There is one outstanding approval per run (keyed by `run_id`), so the
  call needs only `run_id` + `choice` (`once`/`session`/`always`/`deny`). ⚠️
  `always` writes a permanent server `command_allowlist` entry and `session`
  auto-approves for the rest of the gateway session — prefer `once`/`deny` unless
  those side effects are intended. (Gating is only active under
  `approvals.mode: manual` with a non-container backend.)

### `client.jobs` — Jobs API (scheduled background work, under `/api/jobs`)

```ruby
client.jobs.list                              # GET    /api/jobs          => [Job]
client.jobs.create(name:, schedule:,          # POST   /api/jobs          => Job
                   prompt: nil, repeat: nil, deliver: nil,
                   skills: nil, script: nil, no_agent: nil)
client.jobs.get(job_id)                       # GET    /api/jobs/{id}      => Job
client.jobs.update(job_id,                    # PATCH  /api/jobs/{id}      => Job
                   name: nil, schedule: nil, prompt: nil, repeat: nil,
                   deliver: nil, skills: nil, script: nil, no_agent: nil)
client.jobs.delete(job_id)                    # DELETE /api/jobs/{id}      => true (server: {ok:true})
client.jobs.pause(job_id)                     # POST   /api/jobs/{id}/pause  => Job
client.jobs.resume(job_id)                    # POST   /api/jobs/{id}/resume => Job
client.jobs.trigger(job_id)                   # POST   /api/jobs/{id}/run    => Job (fire out-of-schedule)
```

(Plus `**extra` on `create`/`update`, per the request-parameter convention —
omit nil fields from the body. The endpoints live under `/api/jobs`, not `/v1`,
so `Jobs` carries its own prefix. Full request/entity/lifecycle/error wire detail:
[`hermes-api-server.md`](hermes-api-server.md) → Jobs API.)

**Client API decisions:**

- **`trigger`, not `run`, for `POST /api/jobs/{id}/run`** — matches the docs' verb
  and avoids colliding with the `runs` resource. It is **asynchronous**: it returns
  the `Job` (with `next_run_at` advanced), not the run's result.
- **A reaped job is a plain `404`.** One-shot and `repeat.times`-capped jobs are
  **deleted by the server once exhausted** — there is no terminal job *state*, so
  `get`/`trigger` on such a job raise `NotFoundError` like any 404. Documented on
  those methods: a client cannot poll a finished one-shot job for its outcome.
- **Params exposed:** `name`/`schedule` (required), `prompt`, `repeat`, `deliver`,
  `skills`, plus `script`/`no_agent`. The server **silently drops `script`/`no_agent`**
  and **ignores `model`/`provider`/`base_url`/`workdir`/`profile`/`context_from`** —
  so the latter group is **not** exposed as params (read-only entity readers only),
  while `script`/`no_agent` are kept as **no-ops on this server** for forward-compat.
- **`include_disabled:`** on `list` → the undocumented `?include_disabled=true`
  query param (default excludes disabled/paused jobs).

**`Job` entity modeling** (follow [[entity-conventions]] — a reader for every
field in the entity table in `hermes-api-server.md`; here are the resource-
specific decisions that convention alone doesn't settle):

- Wrap the two nested objects as their own prefixed sub-entities (one file,
  `entities/job.rb`, holds all three — as `run.rb` holds `Run`/`RunUsage`/etc.):
  - **`JobSchedule`** for `schedule` — a **tagged union on `kind`**, modeled the
    way `RunEvent` handles its heterogeneous `event` field: one wrapper with a
    `kind` reader, `once?`/`interval?`/`cron?` predicates, `display`, and a
    reader for each kind's payload (`run_at`, `minutes`, `expr`) that is `nil`
    when not of that kind. (Do **not** make polymorphic subclasses.)
  - **`JobRepeat`** for `repeat` — `times` (nullable) and `completed`.
- **`origin` and `enabled_toolsets` are always `null` via this API** (the wire
  doc explains why and gives their internal shapes). Keep them as plain
  passthrough readers (raw value / `nil`), with `#to_h` / `#[]` as the escape
  hatch — do **not** invent wrapper classes.
- Boolean readers `enabled?` / `no_agent?` (per the boolean-reader convention).
- **Timestamps stay strings.** `created_at` / `next_run_at` / `last_run_at` /
  `paused_at` are **ISO-8601 strings with offset** — unlike the runs/responses
  epoch-float timestamps. Expose them verbatim (no Time parsing); just note the
  format difference so no one assumes the runs convention.
- `#id` is the natural reader for the `id` field (no aliasing needed — contrast
  `Run#id`, which aliases `run_id`).

**Implementation notes for the resource** (all now implemented and verified
against the live `hermes-test` gateway):

- **`Transport#patch`** was added (plus `FakeTransport#patch`). No jobs endpoint
  returns session-continuity headers, so `patch` returns the **bare parsed body**
  (like `get`/`delete`), not a `Transport::Result`. `create`/`pause`/`resume`/
  `trigger` go through `post`; the resource just takes `.body` off its `Result`.
- **`pause`/`resume`/`trigger` are body-less POSTs** (no JSON body sent).
- **`delete` maps `{ok: true}` → `true`** (the only endpoint not returning a job).
- **Surprising error mapping to document + test:** `create`/`update` with an
  unparseable `schedule` raises **`ServerError` (500)**, not `BadRequestError`,
  even though it's really invalid input (see Errors). The other validation
  failures (missing `name`/`schedule`, bad id) are the expected `400`/`404`. Note
  this in the method YARD so callers aren't surprised.

### `client.models` / `client.capabilities` — discovery (`/v1`)

```ruby
client.models.list      # GET /v1/models        => [Model]
client.capabilities.get # GET /v1/capabilities   => Capabilities
                        #   (chat_completions, responses_api, run_submission, ...)
```

Both are cheap, offline-friendly (no LLM call). `Capabilities` wraps the
`/v1/capabilities` object (`features` matrix + `endpoints` map — the server's own
route advertisement); `Model` wraps each entry of the `/v1/models` list. **Both
lists are hardcoded single-element / non-paginating server-side**, so the
plain-Array convention is permanently safe here. `Model#permission` is **not**
exposed as a reader — the field is a structurally-always-empty `[]` (as are the
`logprobs: []` arrays in chat/Responses output). Wire shapes:
[`hermes-api-server.md`](hermes-api-server.md) → Discovery.

### `client.health` — health (root paths, no `/v1`)

```ruby
client.health.check     # GET /health           => Health  (#status == "ok")
client.health.detailed  # GET /health/detailed   => HealthDetails
```

`HealthDetails` is an **independent `Entity`** (not a `Health` subclass) with a
reader for every field of the detailed body (`status`, `platform`,
`gateway_state`, `platforms`, `active_agents`, `exit_reason`, `updated_at`,
`pid`). Its `platforms` reader returns a `Hash` keyed by platform name whose
values are **`PlatformStatus`** sub-entities (`state`, `error_code`,
`error_message`, `updated_at`) rather than raw hashes. Wire shapes:
[`hermes-api-server.md`](hermes-api-server.md) → Health.

## Internal layering

- **`Transport`** is the single chokepoint for HTTP: it owns the `http` gem
  connection, attaches the `Authorization` (and optional `Idempotency-Key`)
  headers, serializes/parses JSON, maps status codes to the error hierarchy,
  and exposes `get` / `post` / `delete` / `patch`. `post` (and
  `stream_post`) take an optional `headers:` for per-request headers (e.g. the
  session-continuity headers) and return a `Transport::Result` (`body` +
  normalized, downcased-key response `headers`); `get` / `delete` return the
  bare parsed body, since no caller needs their headers. It also opens SSE
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
  event wrapper, and implements the block-or-enumerator contract. The
  `event_class:` may be a single `Entity` subclass (wrapping every frame) or a
  callable that picks the class from the frame's SSE `event:` name — the latter
  lets one stream surface heterogeneous events (chat uses it to route
  `hermes.tool.progress` frames to `ChatToolProgress` and everything else to
  `ChatCompletionChunk`; Responses passes a single class since its event
  identity is carried in-payload as `type`). It is single-pass and
  HTTP-agnostic (it consumes anything yielding String chunks via `#each`), and
  builds the final aggregated object via an injected aggregator — for chat,
  `ChatCompletion.from_chunks`, which ignores non-chunk events (the chat stream
  sends no final aggregate object, so it is reconstructed from the deltas).
- **`Entity`** is the wrapper base (method readers + `#to_h` + `#[]`).
- **JSON parsing has one chokepoint, `Util.parse_json`** (used by both
  `Transport#handle` and `Stream#dispatch`): a body expected to be JSON but
  unparseable raises **`MalformedResponseError`** — a direct `Error` subclass, not
  an `APIError` (the HTTP request itself succeeded), carrying the raw text as
  `#body` and the `JSON::ParserError` as `#cause`. This is distinct from a non-JSON
  *error* body, which `APIError.parse_error_payload` deliberately tolerates (raw
  text fallback for the router-level bare-text 404/405s — see Errors).

This keeps auth, error mapping, and JSON handling in one place and makes the
resource classes trivial to add as we map more of the API.

## Known limitations & deferred work

The endpoint request/response shapes, SSE events, error families, lifecycle, and
pagination questions that this section once tracked are all resolved — their
findings now live in the resource sections above and in
[`hermes-api-server.md`](hermes-api-server.md). What remains:

- **Chat aggregation assumes a single choice.** The server ignores OpenAI `n` and
  always returns one `choices[0]` (see Chat), so `ChatCompletion.from_chunks`
  reconstructs only `choices[0]` and the per-chunk readers read `choices.first`.
  The aggregator is deliberately **left un-generalized** against this unused
  surface; the raw per-choice data is still reachable via `ChatCompletionChunk#to_h`
  if a future deployment honors `n` — only then generalize.
- **No retry/backoff** in v1 (none planned unless the server signals retryable
  conditions).
- Field mappings remain **best-effort pre-1.0**; `#to_h` / `#[]` and `**extra`
  are the escape hatches as the API surface firms up.
