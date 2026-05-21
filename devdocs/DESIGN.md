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
- Minimal dependencies: [`http`](https://github.com/httprb/http) for requests
  and [`ld-eventsource`](https://github.com/launchdarkly/ruby-eventsource) for
  Server-Sent Event streams.

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
  object.rb           # HermesAgent::Client::Object      (base wrapper)
  errors.rb           # HermesAgent::Client::Error and subclasses
  resources/          # one file per resource group
    chat.rb, responses.rb, runs.rb, jobs.rb,
    models.rb, capabilities.rb, health.rb
  objects/            # response wrappers (best-effort field readers)
    chat_completion.rb, response.rb, run.rb, job.rb, model.rb, ...
```

### Request parameters

- Request parameters are passed as **keyword arguments** using snake_case
  Ruby names, serialized to the JSON field names the server expects.
- Because the field set is not fully known, each request method also accepts an
  open `**extra` (merged into the request body) so callers can pass fields we
  have not yet modeled without waiting on a gem release.
- `model:` is optional everywhere. The server treats it as cosmetic (the actual
  LLM is configured server-side); when omitted we send nothing and let the
  server default to the profile name.

### Return values

- Successful calls return **lightweight wrapper objects** (subclasses of
  `HermesAgent::Client::Object`). Wrappers expose method readers for the fields
  we know about and always provide `#to_h` returning the full parsed payload —
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

### Streaming

Any method that can stream accepts `stream: true` and follows a
**block-or-enumerator** pattern, implemented once in `Stream`:

- With a block, it yields each parsed event as it arrives (natural backpressure)
  and returns the final aggregated object when the stream closes.
- Without a block, it returns a `Stream` (an `Enumerable`) the caller iterates.

```ruby
# block form
client.chat.create(messages: msgs, stream: true) do |event|
  print event.delta
end

# enumerator form
stream = client.chat.create(messages: msgs, stream: true)
stream.each { |event| print event.delta }
```

Events are wrapper objects too. Chat streaming surfaces the server's custom
`hermes.tool.progress` events as a distinct event type (separate from text
deltas) so tool activity does not pollute assistant text.

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

## Resource API

Method signatures below are the intended high-level surface; exact body/field
lists are filled in as we map them. `**extra` is omitted for brevity but
present on every request method.

### `client.chat` — Chat Completions (`POST /v1/chat/completions`, stateless)

```ruby
client.chat.create(messages:, model: nil, stream: false, &block)
  # => ChatCompletion, or streams ChatCompletionChunk / ToolProgress events
```

- `messages` is the OpenAI-style array; content may include `image_url` parts
  (http(s) or `data:` URIs) for inline images.
- OpenAI-compatible on the wire; additional sampling params flow through.

### `client.responses` — Responses API (`/v1/responses`, server-side state)

```ruby
client.responses.create(input:, model: nil,
                        previous_response_id: nil,  # chain a prior turn
                        conversation: nil,           # named conversation
                        stream: false, &block)       # => Response
client.responses.get(id)      # GET    /v1/responses/{id}  => Response
client.responses.delete(id)   # DELETE /v1/responses/{id}  => deletion result
```

- Server persists conversation state; chain multi-turn either by passing the
  prior `previous_response_id` or a stable `conversation` name.
- Inline images supplied as `input_image` input parts.
- Storage is capped server-side (~100 responses, LRU eviction) — callers should
  not assume older responses remain retrievable.

### `client.runs` — Runs API (long-running agent runs)

```ruby
client.runs.create(...)            # POST /v1/runs              => Run (has #id / run_id)
client.runs.get(run_id)            # GET  /v1/runs/{id}         => Run (poll state)
client.runs.events(run_id, &block) # GET  /v1/runs/{id}/events  => SSE stream
client.runs.stop(run_id)           # POST /v1/runs/{id}/stop    => Run/result
```

- `events` uses the same block-or-enumerator streaming pattern over the SSE
  endpoint, yielding run-progress events.

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

### `client.models` / `client.capabilities` — discovery (`/v1`)

```ruby
client.models.list      # GET /v1/models        => [Model]
client.capabilities.get # GET /v1/capabilities   => Capabilities
                        #   (chat_completions, responses_api, run_submission, ...)
```

### `client.health` — health (root paths, no `/v1`)

```ruby
client.health.check     # GET /health           => Health  (#status == "ok")
client.health.detailed  # GET /health/detailed   => detailed Health (sessions,
                        #   running agents, resource usage)
```

## Internal layering

- **`Transport`** is the single chokepoint for HTTP: it owns the `http` gem
  connection, attaches the `Authorization` (and optional `Idempotency-Key`)
  headers, serializes/parses JSON, maps status codes to the error hierarchy,
  and exposes `get` / `post` / `patch` / `delete`. It also opens SSE streams
  (handing the connection to `Stream`).
- **Resource objects** are thin: they build paths and params and delegate to
  `Transport`, wrapping results in the appropriate `Object` subclass.
- **`Stream`** wraps `ld-eventsource`, parses events into wrapper objects, and
  implements the block-or-enumerator contract.
- **`Object`** is the wrapper base (method readers + `#to_h` + `#[]`).

This keeps auth, error mapping, and JSON handling in one place and makes the
resource classes trivial to add as we map more of the API.

## Open questions / to confirm

These need additional docs or experimentation against a live server:

- Exact request bodies and response field names for each endpoint (especially
  `runs` and `jobs`, which the published docs barely detail).
- The full set of SSE event types and payloads for chat streaming and run
  events, including the shape of `hermes.tool.progress`.
- Whether list endpoints (`jobs`, `models`) paginate or always return full
  arrays.
- Structured error response shape (for `APIError#error`).
- Final name of the client-side API-key environment variable.
- Whether a convenience helper for `conversation` chaining is worth adding.
- Retry/backoff policy (none planned for v1 unless the server signals retryable
  conditions).
