# Release History

### v0.1.0 / 2026-05-26

* ADDED: Implement health check endpoint access
* ADDED: Flesh out the error class hierarchy and status mapping
* ADDED: Add detailed health check (client.health.detailed)
* ADDED: Wrap HealthDetails platform values in PlatformStatus entities
* ADDED: Harden Entity as a frozen, value-equal base class
* ADDED: Add capabilities resource (client.capabilities.get)
* ADDED: Add models resource (client.models.list)
* ADDED: Add non-streaming chat resource (client.chat.create)
* ADDED: Add chat streaming (client.chat.stream_create) with in-house SSE
* ADDED: Add Transport#delete for DELETE requests
* ADDED: Add Responses API resource (create/get/delete)
* ADDED: Add Responses API streaming (responses.stream_create)
* ADDED: Add ChatToolProgress entity for hermes.tool.progress events
* ADDED: Let Stream dispatch frames by SSE event name
* ADDED: Surface hermes.tool.progress as ChatToolProgress in chat stream
* ADDED: Add id/status/output_text readers to ResponseOutputItem
* ADDED: Add session-continuity header support
* ADDED: Add Runs resource with create and get
* ADDED: Add Runs stop
* ADDED: Add Runs stream_events
* ADDED: Add Runs respond_approval
* ADDED: Add Transport#patch for PATCH requests
* ADDED: Parse the jobs flat-string error envelope in APIError
* ADDED: Add jobs resource and Job entity
* ADDED: Add Conversation helper for auto-chaining Responses turns
* ADDED: Expose run failure error on Run and RunEvent
* ADDED: Add include_disabled option to jobs.list
* ADDED: Add idempotency_key option to chat.create and responses.create
* ADDED: Reuse a persistent connection per transport
* ADDED: Support a configurable request-write timeout
* FIXED: Use `boolean` yardoc type and `?` names for boolean entity readers
* FIXED: Map mid-stream connection/read failures to the Error hierarchy
* FIXED: Map malformed JSON to MalformedResponseError uniformly
* FIXED: Normalize error-response headers to match the success path
* FIXED: Coerce a nil entity payload to an empty hash
* FIXED: Coerce capability/feature ?-readers to strict booleans
* DOCS: Clarify Job#last_status/#last_error for failed runs
* DOCS: Additional content in the README
* DOCS: Note that a client is not thread-safe in the README
* DOCS: Hide internal-only API from generated YARD docs
* DOCS: Hide error constructors/from_response and scrub internal refs from prose
* DOCS: Record retry/backoff as won't-build and document RateLimitError
* DOCS: Ensure the client class is included in yardocs
* DOCS: Updated a stale note in the docs
* DOCS: One more readme update
