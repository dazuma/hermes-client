# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status

This gem is an early-stage stub. `HermesAgent::Client` is currently an empty
class; the client implementation has not been written yet. The tooling,
packaging, and CI are fully set up, so most work here is building out the
actual API client against the Hermes API Server (see below).

**Read [`devdocs/DESIGN.md`](devdocs/DESIGN.md) first.** It specifies the
conventions, namespacing, resource API, return-value/streaming/error models,
and internal layering the implementation should follow, plus the open questions
still to resolve. It is the source of truth for design decisions; keep it
updated as the design evolves. (`devdocs/` is excluded from the packaged gem.)

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
- **Dependencies:** the client is built on the [`http`](https://github.com/httprb/http) gem (`~> 6.0`) for HTTP requests and [`ld-eventsource`](https://github.com/launchdarkly/ruby-eventsource) (`~> 2.6`) for consuming the Server-Sent Event streams the API emits.
- **Ruby support:** `required_ruby_version >= 3.4`. All files use `# frozen_string_literal: true`.
- **Docs as a gate:** because `toys yardoc` fails on undocumented objects, document public API as you add it.
- **Commit messages:** Use Conventional Commits prefixes. Use `chore:` for changes that are not shipped in the packaged gem (e.g. `devdocs/`, tooling, CI), and reserve `feat:`/`fix:`/etc. for changes to the gem's user-visible code.

## Testing conventions

- Tests use Minitest spec-style `describe` and `it` blocks, with traditional assertions, e.g. `assert_equal`, instead of `must`/`wont` expectations.
- Tests that need to hit a real Hermes gateway should be guarded behind a check whether the environment variable `HERMES_CLIENT_INTEGRATION_PORT` is set. Such tests can use the value of that variable as the port number of the gateway. This variable will be set by the Toys test tool when `--integration-port=<PORT NUMBER>` and `--integration-profile=hermes-test` are passed to `toys test`.

## Exploring real server behavior (`toys gateway`)

The published API docs are thin on request/response field details and SSE event
shapes, so `devdocs/DESIGN.md`'s field lists are best-effort. The `toys gateway`
tools exist to resolve those gaps empirically: they spin up a local gateway and
hit its endpoints with **raw HTTP**, printing prettified JSON (and raw SSE
frames). They deliberately **bypass the client library** so you see the server's
unvarnished wire format — not whatever the entity wrappers would surface. Use
them to answer "what does the server actually return?", then fold durable
findings into `devdocs/DESIGN.md` (marked as observed/best-effort).

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

- `toys gateway probe <METHOD> <PATH> [--body=JSON] [--stream] [--token=TOKEN]` —
  the generic escape hatch. Bearer token defaults to the recorded key.
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
- **Streaming:** responses stream as SSE. Chat completions emit custom `hermes.tool.progress` events for tool execution; the Responses API uses OpenAI-style event types (`function_call`, `function_call_output`, etc.). This is why `ld-eventsource` is a dependency.
