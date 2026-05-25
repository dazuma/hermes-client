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
  - `404` on a run route with an unknown/evicted id (`GET /v1/runs/{bad}`,
    `POST .../stop`, `POST .../approval`) → `{message: "Run not found: ...",
    type: "invalid_request_error", param: null, code: "run_not_found"}`
    (run-existence is checked **before** the body, so a bad `run_id` 404s
    regardless of body)
  - `400` bad approval choice (`POST /v1/runs/{id}/approval`) → `{message:
    "Invalid approval choice; expected one of: once, session, always, deny",
    type: "invalid_request_error", param: null, code: "invalid_approval_choice"}`
  - `400` wrong `conversation_history` type (`POST /v1/runs`) → `{message:
    "'conversation_history' must be an array of message objects", type:
    "invalid_request_error"}`
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
    layer routes them — by SSE event name — to the distinct
    `ChatToolProgress` event type (still yielded to the caller's block) and
    keeps them out of the `ChatCompletion.from_chunks` delta aggregation.
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
    `response.function_call_arguments.delta` streaming). As with chat, `status`
    is lifecycle-only: a tool that *times out* (`"[Command timed out after
    60s]"`) still reports `status: "completed"`, and the model recovers by
    calling another tool.
  - **Reconciled — `output` shape and `id`/`status` differ by representation**
    (probed by running one `terminal` turn and capturing its stream, its
    non-streaming POST, and a GET of the same id):
    - A `function_call_output`'s **`output`** is an **array of content parts**
      (`[{ type: "input_text", text }]`, the `text` itself a JSON string) in
      **every streaming** form — both the per-item `output_item.added`/`.done`
      events *and* the terminal `response.completed.output` — but a **raw JSON
      string** in the **non-streaming** POST and GET bodies. So the *same*
      `output` field is an Array on a streamed `Response` and a String on a
      fetched/created one; the client tolerates both (`ResponseOutputItem#output`
      passes the raw value through, and `#output_text` normalizes to the
      string).
    - Output-item **`id`** (`fc_…`/`fco_…`/`msg_…`) and **`status`** appear
      **only** on items inside the per-item streaming events; they are absent
      from the non-streaming `output` array *and* from the streamed terminal
      `response.completed.output`. So `ResponseOutputItem#id`/`#status` are
      populated for items obtained via stream events and `nil` for items read
      off a final `Response#output`.
- **Runs API** (`runs.stream_events`, `GET /v1/runs/{id}/events`) streams
  **plain `data:` frames** — no SSE `event:` line and **no `[DONE]` sentinel**
  (unlike *both* chat and Responses) — each carrying its type in an **`"event"`
  string field** plus `run_id` and a float `timestamp`. There is **no
  `run.started`** head frame: the stream begins at the first content event, and
  `create`'s `status: "started"` is the only start signal. Observed types:
  - `tool.started` (`tool`, `preview`) and `tool.completed` (`tool`, `duration`
    float, `error` boolean) bracket each tool call. As in the other streams
    `error` is the *result* signal, not lifecycle: a failing command — or a
    **denied** approval — gives `error: true` yet the run still completes; an
    **approved** one gives `error: false`.
  - `message.delta` (`delta` chunk) and `reasoning.available` (`text`, full
    string) carry assistant output.
  - Terminal: `run.completed` (`output` full string, `usage`
    `{input,output,total}_tokens`) on success, or `run.cancelled` (carries
    *only* `event`/`run_id`/`timestamp` — no `output`/`usage`) after a `stop`;
    when a run is stopped before doing any work, that single frame is the entire
    replay. (`run.failed` is presumed but was not reproduced.)
  - **Approval frames** for a gated tool: `approval.request` (`command`,
    `pattern_key`, `pattern_keys[]`, `description`, `choices[]`) when the run
    parks at `waiting_for_approval`, then `approval.responded` (`choice`,
    `resolved`) once the caller answers via `respond_approval` (see the runs
    resource section).
  - Replay is retention-bounded: subscribing to an already-terminal run still
    works briefly, then `404`s — that expiry is **not** a function of how the
    run ended (completed and cancelled both replay until eviction).

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
  the server's own `API_SERVER_KEY`).
- Mutating requests accept an optional `idempotency_key:` sent as the
  `Idempotency-Key` header (server dedupes within ~5 minutes).
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
client.chat.create(messages:, session_id:, session_key:)        # => ChatCompletion
client.chat.stream_create(messages:, session_id:, session_key:, &block)
                                              # streams ChatCompletionChunk /
                                              #   ToolProgress events
```

- `messages` is the OpenAI-style array; content may include `image_url` parts
  (http(s) or `data:` URIs) for inline images.
- `session_id:` / `session_key:` are optional; when given they are sent as the
  `X-Hermes-Session-ID` / `X-Hermes-Session-Key` request headers. The returned
  `ChatCompletion` exposes the server's `#session_id` / `#session_key` (read
  from the response headers) regardless of whether they were sent.
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
- No `session_id:` / `session_key:` params: this endpoint ignores those request
  headers. The returned `Response` from `create` / `stream_create` still exposes
  the server-generated `#session_id` (read from the response header);
  `responses.get` returns no session header, so its `#session_id` is `nil`.
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
    only the `message` items' text. (Note: in the **streaming** representation
    `output` is instead an array of content parts and items carry `id`/`status`
    — see the reconciliation note under "Observed streaming event types".)
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
immediately (HTTP `202`) with only `{ run_id, status: "started" }`, and progress
is tracked by polling `get` or subscribing to `stream_events`. `run_id` is
`run_` + 32 lowercase hex chars. (All shapes below were probed against
`hermes-test`; folded from `devdocs/hermes-api-server.md`.)

- Create body:
  - `input:` (**required**, String) — the user prompt; a body of just `{input}` works.
  - `instructions:` — a system directive layered over the agent prompt (**verified honored**).
  - `conversation_history:` — an **OpenAI-style message array** (`[{role, content}, …]`),
    loaded into context. **Server-validated**: a non-array → `400
    "'conversation_history' must be an array of message objects"`.
  - `previous_response_id:` — loads a stored `/v1/responses` response's context
    into the run. **Load-if-present, not validated**: an unknown id is silently
    ignored (still `202`, run completes, no context loaded) — contrast
    `conversation_history`.
  - `session_id:` — a **correlation label only**, stored and echoed back in the
    poll (defaults to the `run_id`). It is **not** inline conversation context
    and did not observably scope a searchable history — confirm session
    semantics from the server, not the flaky test gateway.
  - No `model:` is sent (server configures the model); whether the endpoint
    accepts one is unconfirmed. Unmodeled fields go via `**extra`.
  - (Prior-context fields were verified by **token accounting** — `usage.input_tokens`
    rises when context loads — because the test gateway's persistent-memory
    confabulation makes content-recall checks unreliable.)
- `Run` (returned by both `create` and `get`; `#id` aliases `#run_id`):
  `object: "hermes.run"`, `run_id`, `status`, `created_at`/`updated_at` (epoch
  floats), `session_id`, `model`, `last_event`, `output`, `usage`
  (`{input,output,total}_tokens`). **`output` and `usage` are nullable** —
  present on a `completed` run but **absent when `cancelled`** (and before
  terminal) — so readers must tolerate `nil`. `create`'s minimal Run carries
  only `run_id` + `status`.
- Status lifecycle: `started` → `running` → terminal `completed` | `cancelled`
  | `failed` (`failed` not yet reproduced); a gated tool parks the run at
  **`waiting_for_approval`**, and `stop` adds a transient `stopping`. Run
  records — and especially the event buffer — are retained only **briefly**
  after terminal, then evicted (`get`/`stop`/`approval` → `404 run_not_found`).
- `stop` returns `200 { run_id, status: "stopping" }` (cooperative; the run then
  resolves to `cancelled`). It need not model as a `Run` — a small ack suffices.
- `stream_events` uses the same block-or-enumerator pattern, but over **plain
  `data:` frames** (no SSE `event:` line, no `[DONE]` sentinel — unlike *both*
  chat and Responses); the event type is an `"event"` string field inside each
  payload. See "Observed streaming event types". Replay works for an
  already-terminal run during the retention window.

**Approval workflow** (human-in-the-loop dangerous-command gating; only active
when the server profile is in `approvals.mode: manual` with a non-container
backend — container backends skip the checks):

- When the agent attempts a dangerous command (`rm -r`, `dd if=`, `DROP TABLE`,
  `> /etc/`, …), the run parks at `waiting_for_approval` and the event stream
  emits **`approval.request`** (`command`, `pattern_key`, `pattern_keys[]`,
  `description`, `choices: [once, session, always, deny]`). There is **no
  approval id** — the pending approval is keyed by `run_id` (one outstanding per
  run), so `respond_approval` needs only the `run_id` + `choice`.
- `respond_approval(run_id, choice:)` → body `{"choice": "<once|session|always|
  deny>"}`. Invalid choice → `400 invalid_approval_choice` (message lists the
  four valid values). Success → `200 { object: "hermes.run.approval_response",
  run_id, choice, resolved }` (`resolved` = count resolved), and the stream
  emits **`approval.responded`** (`choice`, `resolved`).
- **No auto-timeout** observed: a parked run waited ~89s with no auto-deny
  despite the docs' `approvals.timeout: 60` — treat a gated run as blocking
  **indefinitely** pending a response.
- Outcome: **deny** → the gated `tool.completed` carries `error: true` and the
  agent narrates an abort, **but the run still ends `completed`** (deny ≠
  failure). **approve** (`once` verified) → the tool executes, `tool.completed`
  carries `error: false`, the run resumes to `completed`. The only wire
  difference between the two is `tool.completed.error`. ⚠️ `always` writes a
  permanent `command_allowlist` entry (server config mutation) and `session`
  auto-approves the pattern for the rest of the gateway session — prefer
  `once`/`deny` unless those side effects are intended.
- `/v1/capabilities` advertises all five run routes and the
  `run_submission`/`run_status`/`run_events_sse`/`run_stop`/`run_approval_response`
  + `approval_events`/`tool_progress_events` features.

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
omit nil fields from the body. Do **not** add `model:`/`provider:`/`base_url:`/
`workdir:`/`profile:`/`context_from:` params — the API ignores them, see below.)

- Note these live under `/api/jobs`, not `/v1` — `Jobs` carries its own prefix.
- The Jobs endpoints were **not** present in the `hermes-test`
  `/v1/capabilities` advertisement, so they may be gated, versioned separately,
  or absent in some builds — confirm against a server that exposes them.

**Locked design decisions (2026-05-24):**

- **`trigger`, not `run`, for `POST /api/jobs/{id}/run`.** Matches the docs page's
  own verb ("Trigger the job to run immediately") and avoids colliding with the
  `runs` resource's vocabulary. The call is **asynchronous** — it advances the
  job's `next_run_at` to "now" for the scheduler's next tick and returns the
  `Job`; it does **not** block on or return the run's result.
- **`get` on a reaped job raises `NotFoundError` like any 404 — no special
  "gone" return.** One-shot (`once`) jobs and `repeat.times`-capped jobs are
  **deleted by the server once exhausted** (verified live: a `once` job is gone
  after its single fire; a `repeat:2` job survived run #1 then vanished after run
  #2). There is no terminal job *state* to observe — `GET` simply starts
  returning `404 Job not found`. Document this on `get`/`trigger`: a client
  cannot poll a one-shot or final-run job for its outcome after it completes.

**Wire details confirmed by probing (see `hermes-api-server.md` for the full
writeup):**

- `create` **requires** `name` and `schedule`; also accepts `prompt`, `repeat`
  (int), `deliver`, `skills`/`skill`, `script`, `no_agent`. `schedule` is a
  string parsed server-side into a tagged-union (`once`/`interval`/`cron`).
  Returns **`200`** (not the runs `202`).
- `update` (PATCH) is a partial merge over the same writable fields and
  **re-parses `schedule`** (recomputing `next_run_at`).
- **`model`/`provider`/`base_url`/`workdir`/`profile`/`context_from` are NOT
  writable via this API** — silently ignored in create/PATCH (stay `null`). Do
  not expose them as `create`/`update` params; they are read-only entity readers.
- **Mixed error envelope:** auth `401` is the nested `/v1` shape
  (`{error:{message,type,code}}`); jobs business errors (`400`/`404`/`500`) are a
  **flat** `{error: "<string>"}`. `APIError` parsing must accept both. (Bad
  `schedule` is a `500`; bad `deliver` is **not** validated on write.)
- `pause`/`resume` are idempotent (no error when already in the target state).

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
- **`origin` and `enabled_toolsets` were never observed populated** (always
  `null`), so their element shapes are unknown. Do **not** invent empty wrapper
  classes for them — follow the `Model#permission` precedent: expose them as
  plain passthrough readers (raw value / `nil`), with `#to_h` / `#[]` as the
  escape hatch if a real shape ever appears. `enabled_toolsets`, if it ever
  populates, is expected to be a plain array (names), not objects.
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
  even though it's really invalid input (see the mixed-envelope note). The other
  validation failures (missing `name`/`schedule`, bad id) are the expected
  `400`/`404`. Note this in the method YARD so callers aren't surprised.

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

This keeps auth, error mapping, and JSON handling in one place and makes the
resource classes trivial to add as we map more of the API.

## Open questions / to confirm

These need additional docs or experimentation against a live server. The
`toys gateway` tools (start a local gateway, then probe endpoints and dump
prettified JSON / raw SSE frames) are the means to resolve these against a
running server; several below have been refined that way already.

- Exact request bodies and response field names for each endpoint. Discovery,
  chat completions, the Responses API (create/get/delete/stream, incl. the
  non-streaming, deletion, and tool-item output shapes), the **Runs API**
  (create body, poll/status, stop, and the full approval workflow), and the
  **Jobs API** (entity shape, schedule union, create/update/delete/pause/resume/
  trigger, lifecycle, and the mixed error envelope) are now mapped (see above and
  `hermes-api-server.md`). Runs leftovers: whether `create` accepts a `model:`
  field, and the `failed`-status / `run.failed` shape (not reproduced — needs a
  model/infra failure). Jobs leftovers (non-blocking, follow conventions): the
  populated shapes of `origin` / `enabled_toolsets` (always `null` in samples)
  and the failing-run `last_status`/`last_error` shape.
- The full set of SSE event types and payloads. Chat-completion chunks
  (including the custom `hermes.tool.progress` frames), the full Responses API
  event sequence (including the terminal `response.completed`), and the **run
  events stream** (`tool.*`, `message.delta`, `reasoning.available`,
  `run.completed`/`run.cancelled`, `approval.request`/`approval.responded`) are
  now captured (above).
- Whether list endpoints (`jobs`, `models`) paginate or always return full
  arrays. (`models` was observed returning a full `{ object: "list", data }`
  with no pagination fields; `jobs` returns a bare `{ jobs: [...] }` with no
  pagination fields either.)
- ~~Structured error response shape (for `APIError#error`).~~ Captured above:
  **three** families — OpenAI-style `{error: {...}}` for app-level errors
  **and for auth 401 even on `/api/jobs`**; a **flat `{error: "<string>"}`** for
  jobs business errors (`400`/`404`/`500`); and bare text for router-level
  404/405. `APIError` parsing must handle all three. A jobs bad-`schedule` is a
  `500` that is really a user-input rejection, so the `>= 500` ServerError body
  is at least partly characterized now.
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
