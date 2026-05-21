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
- **POST `/v1/runs`** — create an agent run; returns a `run_id`.
- **GET `/v1/runs/{run_id}`** — poll run state.
- **GET `/v1/runs/{run_id}/events`** — Server-Sent Events stream of progress.
- **POST `/v1/runs/{run_id}/stop`** — interrupt a running agent.

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
