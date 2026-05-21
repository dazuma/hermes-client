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
