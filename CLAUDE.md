# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status

This gem is under active development. The client is built out resource by
resource: the `health`, `capabilities`, `models`, `chat` (incl. streaming),
`responses` (incl. streaming), `runs`, and `jobs` resources are **all now
implemented** — the full planned resource surface is in place (verified against
the live `hermes-test` gateway, including jobs CRUD/pause/resume/trigger). The
tooling, packaging, and CI are fully set up. Remaining work is refinement
(see the "Known limitations & deferred work" section of `devdocs/DESIGN.md`),
not new resources.

**Read [`devdocs/DESIGN.md`](devdocs/DESIGN.md) first.** It specifies the
conventions, namespacing, resource API, return-value/streaming/error models,
and internal layering the implementation should follow. It is the source of
truth for client **design** decisions; keep it updated as the design evolves.
Its companion [`devdocs/hermes-api-server.md`](devdocs/hermes-api-server.md) is
the **server wire reference** (endpoints, request/response shapes, error
envelopes, SSE framing, observed behavior). Keep the scope split: server wire
facts live in the wire reference and are cross-referenced from `DESIGN.md`, not
duplicated. (`devdocs/` is excluded from the packaged gem.)

## Commands

Tooling is driven by [toys](https://dazuma.github.io/toys) (`gem install toys`),
not Rake. Bundler is already wired into each tool, and they do not need `bundle exec`.

- `toys ci` — run the full CI suite (bundle, rubocop, tests, yardoc, gem build).
- `toys ci --only --test` — run a single CI job (any of `--bundle`, `--rubocop`, `--test`, `--yard`, `--build`). `--fail-fast` and `--update` are also available.
- `toys test` — run the unit tests only
- `toys test --integration-port=10099 --integration-profile=hermes-test` - run all tests including integration tests against a real test gateway. These flags can also be passed to `toys ci`.
- `toys test test/some_test.rb` — run a single test file.
- `toys rubocop` — run the linter/style checker.
- `toys yardoc` — build docs. **Fails on warnings and on any undocumented object**, so every public method/class needs YARD comments.
- `toys build` / `toys install` — build (and install) the gem.

Run `toys test` and `toys rubocop` before committing.

`minitest-focus` is available: add `focus` above a test method to run only that
one. Tests use minitest (`test/helper.rb` sets up autorun, focus, and rg).

## Architecture & conventions

- **Red-Green TDD:** In most cases, use Red-Green TDD for development. For each development step, write a failing test first, then write code to get the tests to pass, then commit before moving on to the next step.
- **Name vs. namespace mismatch (intentional):** the gem is `hermes-client`, the require entry point is `lib/hermes-client.rb`, but the code lives under the `HermesAgent::Client` module (require path `hermes_agent/client`). `lib/hermes-client.rb` just requires `hermes_agent/client`. Keep new files under `lib/hermes_agent/client/`.
- **Dependencies:** the client is built on the [`http`](https://github.com/httprb/http) gem (`~> 6.0`) for HTTP requests. Server-Sent Event streams are parsed in-house (`HermesAgent::Client::Stream`) over the same `http` connection, so there is no separate SSE dependency.
- **Ruby support:** `required_ruby_version >= 3.4`. All files use `# frozen_string_literal: true`.
- **Docs as a gate:** because `toys yardoc` fails on undocumented objects, document public API as you add it.
- **Commit messages:** Use Conventional Commits prefixes. Use `chore:` for changes that are not shipped in the packaged gem (e.g. `devdocs/`, tooling, CI), and reserve `feat:`/`fix:`/etc. for changes to the gem's user-visible code. Use `docs:` for documentation-only changes — including edits to **shipped** YARD comments in `lib/` (the published API docs), which are not `chore:` because they ship, but not `feat:`/`fix:` because they change no behavior.

## Testing conventions

- Tests use Minitest spec-style `describe` and `it` blocks, with traditional assertions, e.g. `assert_equal`, instead of `must`/`wont` expectations.
- Tests that need to hit a real Hermes gateway should be guarded behind a check whether the environment variable `HERMES_CLIENT_INTEGRATION_PORT` is set. Such tests can use the value of that variable as the port number of the gateway. This variable will be set by the Toys test tool when `--integration-port=<PORT NUMBER>` and `--integration-profile=hermes-test` are passed to `toys test`.
- Integration tests with real side effects or unusual cost are gated behind their own opt-in env var (in addition to `HERMES_CLIENT_INTEGRATION_PORT`), so a tester chooses to run them — e.g. the runs approve-path test, which actually executes a gated command, requires `HERMES_CLIENT_INTEGRATION_APPROVE`.

## Exploring real server behavior (`toys gateway`)

The published API docs are thin on request/response field details and SSE event
shapes, so `devdocs/hermes-api-server.md`'s field lists are best-effort. The `toys gateway`
tools exist to resolve those gaps empirically: they spin up a local gateway and
hit its endpoints with **raw HTTP**, printing prettified JSON (and raw SSE
frames). They deliberately **bypass the client library** so you see the server's
unvarnished wire format — not whatever the entity wrappers would surface. Use
them to answer "what does the server actually return?", then fold durable
findings into `devdocs/hermes-api-server.md` (the wire reference), following its
provenance convention.

**Prerequisite:** the `hermes` CLI must be installed and a `hermes-test` profile
must exist (`hermes profile list` to check) — the same profile the integration
tests use. Defaults: profile `hermes-test`, port `10099`.

**Lifecycle (start once, probe many times):**

- `toys gateway start [--profile=hermes-test] [--port=10099] [--key=KEY]` —
  spawns `hermes -p <profile> gateway run` as a **detached background process**,
  polls `/health`, and records `{pid, port, profile, base_url, key}` in the
  gitignored `tmp/gateway-state.json`. The server key resolves from `--key`,
  else `$API_SERVER_KEY`, else a freshly generated one — whatever is used is
  recorded so probes authenticate automatically. Gateway stdout/stderr is
  captured to `tmp/gateway.log`.
- `toys gateway status` — report whether it is running (and where).
- `toys gateway stop` — SIGINT the process and clear the state file.

Run lifetime spans separate tool invocations (state lives in the file, not the
process), so you can `start` once and probe repeatedly — important for the
**server-side-stateful** endpoints (chain Responses turns, poll a `run_id`).

**Probing:**

- `toys gateway probe <METHOD> <PATH> [--body=JSON] [--stream] [--token=TOKEN]
  [--idempotency-key=KEY] [--show-headers]` — the generic escape hatch. Bearer
  token defaults to the recorded key. `--idempotency-key` sends an
  `Idempotency-Key` header (server dedupes ~5 min); `--show-headers` dumps all
  response headers and the request latency to stderr.
- Shortcuts: `toys gateway models`, `capabilities`, `health [--detailed]`,
  `chat "<text>" [--stream]`,
  `respond "<text>" [--previous=ID] [--conversation=NAME] [--stream]`.

**Output:** the prettified JSON body goes to **stdout**; the `HTTP <status>` line
goes to **stderr**, so `toys gateway probe GET /v1/models > out.json` captures
clean JSON. With `--stream`, the response is read as SSE and rendered
frame-by-frame: the `event:` name when present, then each data payload
prettified as JSON (raw fallback for non-JSON data like the `[DONE]` sentinel).
Add `--stream` *and* set `"stream": true` in the body for a raw `probe`; the
`chat`/`respond` shortcuts set the body flag for you when given `--stream`.

**Example flow:**

```sh
toys gateway start
toys gateway capabilities                       # advertised endpoints + feature matrix
toys gateway probe POST /v1/responses --body '{"input":"hello"}'
toys gateway respond "hello" --stream           # see the named SSE event sequence
toys gateway stop
```

**Notes / gotchas:**

- `hermes-test` runs a **real model** (e.g. `gemini-flash-lite`), so
  `chat`/`respond`/`runs` make real LLM calls (latency, cost, network).
  Discovery (`models`, `capabilities`, `health`) is cheap and offline-friendly.
- The default port `10099` is also what `toys test --integration-port=10099`
  uses; stop a probe gateway (or pick another `--port`) before running
  integration tests so they don't collide on the port.
- Implementation lives in `.toys/gateway/` with shared logic in
  `.toys/gateway/.lib/hermes_gateway.rb`. The `.toys/` tree is **not** covered by
  rubocop or yardoc, so it is exempt from the lint/docs gates. `tmp/` is
  gitignored. These tools are not shipped in the gem (commit them as `chore:`).

## Target API: Hermes API Server

This client wraps the [Hermes API Server](https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server).
Key facts the client must accommodate:

- **Base URL / auth:** defaults to `http://127.0.0.1:8642/v1`. Bearer token auth via the `Authorization` header; the server reads its key from `API_SERVER_KEY`.
- **Endpoints:**
  - `POST /v1/chat/completions` — OpenAI-compatible chat (messages array, inline images via `image_url`).
  - `POST /v1/responses` — Responses API with server-side conversation persistence; chain turns via `previous_response_id` or a named `conversation`.
  - `POST /v1/runs` — long-form streaming runs; returns a `run_id` for progress tracking.
  - `GET /v1/models`, `GET /v1/capabilities` — discovery (advertised models, feature support).
- **Streaming:** responses stream as SSE, parsed in-house by `Client::Stream` over the `http` connection. Chat completions emit custom `hermes.tool.progress` events for tool execution; the Responses API uses OpenAI-style event types (`function_call`, `function_call_output`, etc.).
