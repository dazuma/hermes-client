# frozen_string_literal: true

require "helper"

describe ::HermesAgent::Client::Entities::ChatMessage do
  it "reads the role and content" do
    message = ::HermesAgent::Client::Entities::ChatMessage.new("role" => "assistant", "content" => "Hi there.")
    assert_equal("assistant", message.role)
    assert_equal("Hi there.", message.content)
  end

  it "returns nil for fields when absent" do
    message = ::HermesAgent::Client::Entities::ChatMessage.new({})
    assert_nil(message.role)
    assert_nil(message.content)
  end
end

describe ::HermesAgent::Client::Entities::ChatUsage do
  it "reads the token counts" do
    usage = ::HermesAgent::Client::Entities::ChatUsage.new(
      "prompt_tokens" => 13_950, "completion_tokens" => 3, "total_tokens" => 13_953
    )
    assert_equal(13_950, usage.prompt_tokens)
    assert_equal(3, usage.completion_tokens)
    assert_equal(13_953, usage.total_tokens)
  end

  it "returns nil for fields when absent" do
    usage = ::HermesAgent::Client::Entities::ChatUsage.new({})
    assert_nil(usage.prompt_tokens)
    assert_nil(usage.completion_tokens)
    assert_nil(usage.total_tokens)
  end
end

describe ::HermesAgent::Client::Entities::ChatChoice do
  choice_hash = {
    "index" => 0,
    "message" => {"role" => "assistant", "content" => "Hi there."},
    "finish_reason" => "stop",
  }

  it "reads the index and finish_reason" do
    choice = ::HermesAgent::Client::Entities::ChatChoice.new(choice_hash)
    assert_equal(0, choice.index)
    assert_equal("stop", choice.finish_reason)
  end

  it "wraps the message in a ChatMessage entity" do
    choice = ::HermesAgent::Client::Entities::ChatChoice.new(choice_hash)
    assert_instance_of(::HermesAgent::Client::Entities::ChatMessage, choice.message)
    assert_equal("Hi there.", choice.message.content)
  end

  it "returns nil for fields when absent" do
    choice = ::HermesAgent::Client::Entities::ChatChoice.new({})
    assert_nil(choice.index)
    assert_nil(choice.finish_reason)
    assert_nil(choice.message)
  end
end

describe ::HermesAgent::Client::Entities::ChatCompletion do
  payload = {
    "id" => "chatcmpl-abc123",
    "object" => "chat.completion",
    "created" => 1_779_403_951,
    "model" => "hermes-test",
    "choices" => [
      {"index" => 0, "message" => {"role" => "assistant", "content" => "Hello there."}, "finish_reason" => "stop"},
    ],
    "usage" => {"prompt_tokens" => 13_950, "completion_tokens" => 3, "total_tokens" => 13_953},
  }

  it "reads the scalar fields" do
    completion = ::HermesAgent::Client::Entities::ChatCompletion.new(payload)
    assert_equal("chatcmpl-abc123", completion.id)
    assert_equal("chat.completion", completion.object)
    assert_equal(1_779_403_951, completion.created)
    assert_equal("hermes-test", completion.model)
  end

  it "wraps each choice in a ChatChoice entity" do
    completion = ::HermesAgent::Client::Entities::ChatCompletion.new(payload)
    choices = completion.choices
    assert_kind_of(::Array, choices)
    assert_equal(1, choices.length)
    assert_instance_of(::HermesAgent::Client::Entities::ChatChoice, choices.first)
    assert_equal("Hello there.", choices.first.message.content)
  end

  it "wraps usage in a ChatUsage entity" do
    completion = ::HermesAgent::Client::Entities::ChatCompletion.new(payload)
    assert_instance_of(::HermesAgent::Client::Entities::ChatUsage, completion.usage)
    assert_equal(13_953, completion.usage.total_tokens)
  end

  it "exposes the raw payload via to_h" do
    completion = ::HermesAgent::Client::Entities::ChatCompletion.new(payload)
    assert_equal("Hello there.", completion.to_h["choices"][0]["message"]["content"])
  end

  it "returns nil for fields when absent" do
    completion = ::HermesAgent::Client::Entities::ChatCompletion.new({})
    assert_nil(completion.id)
    assert_nil(completion.object)
    assert_nil(completion.created)
    assert_nil(completion.model)
    assert_nil(completion.choices)
    assert_nil(completion.usage)
  end
end

describe "ChatCompletion session headers" do
  payload = {"object" => "chat.completion"}

  it "exposes session_id and session_key supplied from response headers" do
    completion = ::HermesAgent::Client::Entities::ChatCompletion.new(
      payload, session_id: "sid-1", session_key: "skey-1"
    )
    assert_equal("sid-1", completion.session_id)
    assert_equal("skey-1", completion.session_key)
  end

  it "defaults the session readers to nil" do
    completion = ::HermesAgent::Client::Entities::ChatCompletion.new(payload)
    assert_nil(completion.session_id)
    assert_nil(completion.session_key)
  end

  it "keeps the session values out of the body payload (to_h)" do
    completion = ::HermesAgent::Client::Entities::ChatCompletion.new(
      payload, session_id: "sid-1", session_key: "skey-1"
    )
    assert_equal(payload, completion.to_h)
    refute(completion.to_h.key?("session_id"))
    refute(completion.to_h.key?("session_key"))
  end

  it "factors the session values into equality and hash" do
    base = ::HermesAgent::Client::Entities::ChatCompletion.new(payload, session_id: "s", session_key: "k")
    same = ::HermesAgent::Client::Entities::ChatCompletion.new(payload, session_id: "s", session_key: "k")
    diff_id = ::HermesAgent::Client::Entities::ChatCompletion.new(payload, session_id: "other", session_key: "k")
    body_only = ::HermesAgent::Client::Entities::ChatCompletion.new(payload)
    assert_equal(base, same)
    assert_equal(base.hash, same.hash)
    refute_equal(base, diff_id)
    refute_equal(base, body_only)
  end
end

describe ::HermesAgent::Client::Entities::ChatCompletionChunk do
  let(:role_chunk) do
    {
      "id" => "chatcmpl-1", "object" => "chat.completion.chunk", "created" => 1, "model" => "hermes-test",
      "choices" => [{"index" => 0, "delta" => {"role" => "assistant"}, "finish_reason" => nil}]
    }
  end
  let(:content_chunk) do
    {
      "object" => "chat.completion.chunk",
      "choices" => [{"index" => 0, "delta" => {"content" => "Hello"}, "finish_reason" => nil}],
    }
  end
  let(:final_chunk) do
    {
      "object" => "chat.completion.chunk",
      "choices" => [{"index" => 0, "delta" => {}, "finish_reason" => "stop"}],
      "usage" => {"prompt_tokens" => 1, "completion_tokens" => 2, "total_tokens" => 3},
    }
  end

  it "reads the scalar fields" do
    chunk = ::HermesAgent::Client::Entities::ChatCompletionChunk.new(role_chunk)
    assert_equal("chatcmpl-1", chunk.id)
    assert_equal("chat.completion.chunk", chunk.object)
    assert_equal(1, chunk.created)
    assert_equal("hermes-test", chunk.model)
  end

  it "exposes the incremental content as delta and the role" do
    assert_equal("assistant", ::HermesAgent::Client::Entities::ChatCompletionChunk.new(role_chunk).role)
    assert_equal("Hello", ::HermesAgent::Client::Entities::ChatCompletionChunk.new(content_chunk).delta)
  end

  it "returns nil delta when the chunk carries no content" do
    assert_nil(::HermesAgent::Client::Entities::ChatCompletionChunk.new(role_chunk).delta)
  end

  it "exposes finish_reason and usage on the final chunk" do
    chunk = ::HermesAgent::Client::Entities::ChatCompletionChunk.new(final_chunk)
    assert_equal("stop", chunk.finish_reason)
    assert_instance_of(::HermesAgent::Client::Entities::ChatUsage, chunk.usage)
    assert_equal(3, chunk.usage.total_tokens)
  end

  it "returns nil for fields when absent" do
    chunk = ::HermesAgent::Client::Entities::ChatCompletionChunk.new({})
    assert_nil(chunk.id)
    assert_nil(chunk.delta)
    assert_nil(chunk.role)
    assert_nil(chunk.finish_reason)
    assert_nil(chunk.usage)
  end
end

describe ::HermesAgent::Client::Entities::ChatToolProgress do
  let(:running) do
    {
      "tool" => "search_files",
      "emoji" => "🔎",
      "label" => "*",
      "toolCallId" => "call_6941aca4c0eb",
      "status" => "running",
    }
  end
  let(:completed) do
    {"tool" => "search_files", "toolCallId" => "call_6941aca4c0eb", "status" => "completed"}
  end

  it "reads the tool, emoji, and label" do
    event = ::HermesAgent::Client::Entities::ChatToolProgress.new(running)
    assert_equal("search_files", event.tool)
    assert_equal("🔎", event.emoji)
    assert_equal("*", event.label)
  end

  it "reads the tool_call_id from the camelCase toolCallId wire field" do
    event = ::HermesAgent::Client::Entities::ChatToolProgress.new(running)
    assert_equal("call_6941aca4c0eb", event.tool_call_id)
  end

  it "reads the status and exposes running?/completed? predicates" do
    running_event = ::HermesAgent::Client::Entities::ChatToolProgress.new(running)
    assert_equal("running", running_event.status)
    assert_equal(true, running_event.running?)
    assert_equal(false, running_event.completed?)

    completed_event = ::HermesAgent::Client::Entities::ChatToolProgress.new(completed)
    assert_equal("completed", completed_event.status)
    assert_equal(false, completed_event.running?)
    assert_equal(true, completed_event.completed?)
  end

  it "returns nil for emoji and label on a completed frame, which omits them" do
    event = ::HermesAgent::Client::Entities::ChatToolProgress.new(completed)
    assert_nil(event.emoji)
    assert_nil(event.label)
  end

  it "returns nil/false for fields and predicates when absent" do
    event = ::HermesAgent::Client::Entities::ChatToolProgress.new({})
    assert_nil(event.tool)
    assert_nil(event.emoji)
    assert_nil(event.label)
    assert_nil(event.tool_call_id)
    assert_nil(event.status)
    assert_equal(false, event.running?)
    assert_equal(false, event.completed?)
  end
end

describe "ChatCompletion.from_chunks" do
  let(:chunks) do
    [
      {"id" => "chatcmpl-1", "object" => "chat.completion.chunk", "created" => 7, "model" => "hermes-test",
       "choices" => [{"index" => 0, "delta" => {"role" => "assistant"}, "finish_reason" => nil}]},
      {"object" => "chat.completion.chunk",
       "choices" => [{"index" => 0, "delta" => {"content" => "Hello"}, "finish_reason" => nil}]},
      {"object" => "chat.completion.chunk",
       "choices" => [{"index" => 0, "delta" => {"content" => " world"}, "finish_reason" => "stop"}],
       "usage" => {"prompt_tokens" => 1, "completion_tokens" => 2, "total_tokens" => 3}},
    ].map { |hash| ::HermesAgent::Client::Entities::ChatCompletionChunk.new(hash) }
  end

  it "reconstructs a ChatCompletion from streamed chunks" do
    completion = ::HermesAgent::Client::Entities::ChatCompletion.from_chunks(chunks)
    assert_instance_of(::HermesAgent::Client::Entities::ChatCompletion, completion)
    assert_equal("chatcmpl-1", completion.id)
    assert_equal("chat.completion", completion.object)
    assert_equal(7, completion.created)
    assert_equal("hermes-test", completion.model)
  end

  it "assembles the message from the deltas" do
    completion = ::HermesAgent::Client::Entities::ChatCompletion.from_chunks(chunks)
    choice = completion.choices.first
    assert_equal("assistant", choice.message.role)
    assert_equal("Hello world", choice.message.content)
    assert_equal("stop", choice.finish_reason)
  end

  it "carries the usage from the final chunk" do
    completion = ::HermesAgent::Client::Entities::ChatCompletion.from_chunks(chunks)
    assert_equal(3, completion.usage.total_tokens)
  end

  it "returns an empty-content completion for no chunks" do
    completion = ::HermesAgent::Client::Entities::ChatCompletion.from_chunks([])
    assert_equal("", completion.choices.first.message.content)
  end

  it "carries session headers passed to it onto the assembled completion" do
    completion = ::HermesAgent::Client::Entities::ChatCompletion.from_chunks(
      chunks, session_id: "sid-1", session_key: "skey-1"
    )
    assert_equal("sid-1", completion.session_id)
    assert_equal("skey-1", completion.session_key)
  end

  it "ignores non-chunk events such as ChatToolProgress when assembling" do
    mixed = [
      ::HermesAgent::Client::Entities::ChatToolProgress.new("tool" => "search_files", "status" => "running"),
      ::HermesAgent::Client::Entities::ChatCompletionChunk.new(
        "id" => "c1", "object" => "chat.completion.chunk", "created" => 4, "model" => "m",
        "choices" => [{"index" => 0, "delta" => {"role" => "assistant", "content" => "Hi"}, "finish_reason" => "stop"}]
      ),
      ::HermesAgent::Client::Entities::ChatToolProgress.new("tool" => "search_files", "status" => "completed"),
    ]
    completion = ::HermesAgent::Client::Entities::ChatCompletion.from_chunks(mixed)
    assert_equal("c1", completion.id)
    assert_equal("assistant", completion.choices.first.message.role)
    assert_equal("Hi", completion.choices.first.message.content)
  end
end

describe ::HermesAgent::Client::Resources::Chat do
  let(:transport) do
    ::HermesAgent::Tests::FakeTransport.new("object" => "chat.completion")
  end

  let(:messages) { [{role: "user", content: "hello"}] }

  it "posts to the /v1/chat/completions path" do
    ::HermesAgent::Client::Resources::Chat.new(transport).create(messages: messages)
    assert_equal("/v1/chat/completions", transport.requested_path)
  end

  it "sends the messages in the request body" do
    ::HermesAgent::Client::Resources::Chat.new(transport).create(messages: messages)
    assert_equal(messages, transport.requested_body[:messages])
  end

  it "does not send a model field" do
    ::HermesAgent::Client::Resources::Chat.new(transport).create(messages: messages)
    refute(transport.requested_body.key?(:model))
  end

  it "merges extra keyword arguments into the body" do
    ::HermesAgent::Client::Resources::Chat.new(transport).create(messages: messages, temperature: 0.2)
    assert_in_delta(0.2, transport.requested_body[:temperature])
  end

  it "wraps the response in a ChatCompletion entity" do
    completion = ::HermesAgent::Client::Resources::Chat.new(transport).create(messages: messages)
    assert_instance_of(::HermesAgent::Client::Entities::ChatCompletion, completion)
    assert_equal("chat.completion", completion.object)
  end

  it "sends the idempotency_key as an Idempotency-Key request header" do
    ::HermesAgent::Client::Resources::Chat.new(transport).create(messages: messages, idempotency_key: "abc-123")
    assert_equal("abc-123", transport.requested_headers["Idempotency-Key"])
  end

  it "omits the Idempotency-Key header when no idempotency_key is given" do
    ::HermesAgent::Client::Resources::Chat.new(transport).create(messages: messages)
    refute(transport.requested_headers.key?("Idempotency-Key")) if transport.requested_headers
  end

  it "sends the idempotency key alongside session headers" do
    ::HermesAgent::Client::Resources::Chat.new(transport).create(
      messages: messages, session_id: "sid-1", idempotency_key: "abc-123"
    )
    assert_equal("sid-1", transport.requested_headers["X-Hermes-Session-ID"])
    assert_equal("abc-123", transport.requested_headers["Idempotency-Key"])
  end
end

describe "Resources::Chat#stream_create" do
  let(:stream_chunks) do
    [
      "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"m\"," \
      "\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}\n\n",
      "data: {\"object\":\"chat.completion.chunk\"," \
      "\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n\n",
      "data: {\"object\":\"chat.completion.chunk\"," \
      "\"choices\":[{\"index\":0,\"delta\":{\"content\":\" world\"},\"finish_reason\":\"stop\"}]," \
      "\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":2,\"total_tokens\":3}}\n\n",
      "data: [DONE]\n\n",
    ]
  end
  let(:transport) { ::HermesAgent::Tests::FakeTransport.new({}, stream_chunks) }
  let(:messages) { [{role: "user", content: "hello"}] }

  it "posts to /v1/chat/completions with stream enabled and the messages" do
    ::HermesAgent::Client::Resources::Chat.new(transport).stream_create(messages: messages).result
    assert_equal("/v1/chat/completions", transport.requested_path)
    assert_equal(messages, transport.requested_body[:messages])
    assert_equal(true, transport.requested_body[:stream])
  end

  it "yields ChatCompletionChunk events and returns the assembled ChatCompletion (block form)" do
    deltas = []
    completion = ::HermesAgent::Client::Resources::Chat.new(transport).stream_create(messages: messages) do |event|
      assert_instance_of(::HermesAgent::Client::Entities::ChatCompletionChunk, event)
      deltas << event.delta
    end
    assert_equal([nil, "Hello", " world"], deltas)
    assert_instance_of(::HermesAgent::Client::Entities::ChatCompletion, completion)
    assert_equal("Hello world", completion.choices.first.message.content)
    assert_equal(3, completion.usage.total_tokens)
  end

  it "returns a Stream the caller can iterate (enumerator form)" do
    stream = ::HermesAgent::Client::Resources::Chat.new(transport).stream_create(messages: messages)
    assert_instance_of(::HermesAgent::Client::Stream, stream)
    text = stream.each.filter_map(&:delta).join
    assert_equal("Hello world", text)
    assert_equal("Hello world", stream.result.choices.first.message.content)
  end
end

describe "Resources::Chat#stream_create with tool progress" do
  let(:tool_stream_chunks) do
    [
      "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"m\"," \
      "\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}\n\n",
      "event: hermes.tool.progress\ndata: {\"tool\":\"search_files\",\"emoji\":\"🔎\",\"label\":\"*\"," \
      "\"toolCallId\":\"call_1\",\"status\":\"running\"}\n\n",
      "event: hermes.tool.progress\ndata: {\"tool\":\"search_files\",\"toolCallId\":\"call_1\"," \
      "\"status\":\"completed\"}\n\n",
      "data: {\"object\":\"chat.completion.chunk\"," \
      "\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":\"stop\"}]," \
      "\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":2,\"total_tokens\":3}}\n\n",
      "data: [DONE]\n\n",
    ]
  end
  let(:transport) { ::HermesAgent::Tests::FakeTransport.new({}, tool_stream_chunks) }
  let(:messages) { [{role: "user", content: "list my files"}] }

  it "routes named frames to ChatToolProgress and text frames to ChatCompletionChunk" do
    classes = []
    ::HermesAgent::Client::Resources::Chat.new(transport).stream_create(messages: messages) do |event|
      classes << event.class
    end
    assert_equal(
      [::HermesAgent::Client::Entities::ChatCompletionChunk,
       ::HermesAgent::Client::Entities::ChatToolProgress,
       ::HermesAgent::Client::Entities::ChatToolProgress,
       ::HermesAgent::Client::Entities::ChatCompletionChunk],
      classes
    )
  end

  it "exposes the tool-progress details on the yielded ChatToolProgress events" do
    progress = []
    ::HermesAgent::Client::Resources::Chat.new(transport).stream_create(messages: messages) do |event|
      progress << event if event.is_a?(::HermesAgent::Client::Entities::ChatToolProgress)
    end
    assert_equal("search_files", progress.first.tool)
    assert_equal("*", progress.first.label)
    assert_equal("call_1", progress.first.tool_call_id)
    assert(progress.first.running?)
    assert(progress.last.completed?)
  end

  it "assembles the completion from text chunks only, ignoring tool-progress frames" do
    completion = ::HermesAgent::Client::Resources::Chat.new(transport).stream_create(messages: messages) { |_event| nil }
    assert_equal("Hello", completion.choices.first.message.content)
    assert_equal("assistant", completion.choices.first.message.role)
    assert_equal(3, completion.usage.total_tokens)
  end
end

describe "Resources::Chat session headers" do
  let(:messages) { [{role: "user", content: "hello"}] }

  it "sends session_id and session_key as request headers on #create" do
    transport = ::HermesAgent::Tests::FakeTransport.new("object" => "chat.completion")
    ::HermesAgent::Client::Resources::Chat.new(transport).create(
      messages: messages, session_id: "sid-1", session_key: "skey-1"
    )
    assert_equal("sid-1", transport.requested_headers["X-Hermes-Session-ID"])
    assert_equal("skey-1", transport.requested_headers["X-Hermes-Session-Key"])
  end

  it "omits session request headers when neither is given" do
    transport = ::HermesAgent::Tests::FakeTransport.new("object" => "chat.completion")
    ::HermesAgent::Client::Resources::Chat.new(transport).create(messages: messages)
    assert(transport.requested_headers.nil? || transport.requested_headers.empty?)
  end

  it "reads the response session headers onto the completion from #create" do
    transport = ::HermesAgent::Tests::FakeTransport.new(
      {"object" => "chat.completion"}, [],
      {"x-hermes-session-id" => "sid-2", "x-hermes-session-key" => "skey-2"}
    )
    completion = ::HermesAgent::Client::Resources::Chat.new(transport).create(messages: messages)
    assert_equal("sid-2", completion.session_id)
    assert_equal("skey-2", completion.session_key)
  end

  it "sends session headers and carries response session headers onto the assembled stream completion" do
    chunks = [
      "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"m\"," \
      "\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"hi\"}," \
      "\"finish_reason\":\"stop\"}]}\n\n",
      "data: [DONE]\n\n",
    ]
    transport = ::HermesAgent::Tests::FakeTransport.new({}, chunks, {"x-hermes-session-id" => "sid-3"})
    completion = ::HermesAgent::Client::Resources::Chat.new(transport).stream_create(
      messages: messages, session_id: "sid-3"
    ).result
    assert_equal("sid-3", transport.requested_headers["X-Hermes-Session-ID"])
    assert_equal("sid-3", completion.session_id)
  end
end

describe "chat" do
  integration_port = ENV["HERMES_CLIENT_INTEGRATION_PORT"]

  if integration_port
    let(:client) do
      ::HermesAgent::Client.new(base_url: "http://localhost:#{integration_port}",
                                api_key: ::HermesAgent::Tests.integration_api_key)
    end

    it "completes a chat turn against the live gateway" do
      completion = client.chat.create(messages: [{role: "user", content: "Say hello in exactly two words."}])
      assert_instance_of(::HermesAgent::Client::Entities::ChatCompletion, completion)
      assert_equal("chat.completion", completion.object)
      choice = completion.choices.first
      assert_equal("assistant", choice.message.role)
      refute_empty(choice.message.content)
    end

    it "streams a chat turn against the live gateway" do
      deltas = []
      completion = client.chat.stream_create(messages: [{role: "user", content: "Count: one two three"}]) do |event|
        assert_instance_of(::HermesAgent::Client::Entities::ChatCompletionChunk, event)
        deltas << event.delta
      end
      assert_instance_of(::HermesAgent::Client::Entities::ChatCompletion, completion)
      streamed_text = deltas.compact.join
      refute_empty(streamed_text)
      assert_equal(streamed_text, completion.choices.first.message.content)
    end

    it "surfaces tool-progress events on a tool-executing stream against the live gateway" do
      # The `date` command runs a single fast tool, unlike a directory listing
      # (which triggers a slow, timeout-prone search_files scan).
      prompt = "Please run the shell command 'date' in the terminal and tell me the output."
      progress = []
      chunks = []
      completion = client.chat.stream_create(messages: [{role: "user", content: prompt}]) do |event|
        case event
        when ::HermesAgent::Client::Entities::ChatToolProgress then progress << event
        when ::HermesAgent::Client::Entities::ChatCompletionChunk then chunks << event
        end
      end

      refute_empty(progress, "expected at least one hermes.tool.progress event")
      refute_nil(progress.first.tool)
      refute_nil(progress.first.tool_call_id)
      assert(progress.any?(&:running?), "expected a running event")
      assert(progress.any?(&:completed?), "expected a completed event")

      # Tool frames are routed out of the assembled text, which still arrives
      # via ordinary chunks.
      assert_instance_of(::HermesAgent::Client::Entities::ChatCompletion, completion)
      refute_empty(chunks)
      refute_empty(completion.choices.first.message.content)
    end

    it "returns a server-generated session id and no session key when none is sent" do
      completion = client.chat.create(messages: [{role: "user", content: "Say hello."}])
      refute_nil(completion.session_id, "expected the server to generate a session id")
      refute_empty(completion.session_id)
      assert_nil(completion.session_key, "expected no session key when none was sent")
    end

    it "echoes the supplied session_id and session_key back on the completion" do
      session_id = "sid-#{::SecureRandom.hex(8)}"
      session_key = "skey-#{::SecureRandom.hex(8)}"
      completion = client.chat.create(
        messages: [{role: "user", content: "Say hello."}],
        session_id: session_id, session_key: session_key
      )
      assert_equal(session_id, completion.session_id)
      assert_equal(session_key, completion.session_key)
    end

    it "carries the session id onto the assembled completion when streaming" do
      session_id = "sid-#{::SecureRandom.hex(8)}"
      completion = client.chat.stream_create(
        messages: [{role: "user", content: "Count: one two three"}],
        session_id: session_id
      ) { |_event| nil }
      assert_equal(session_id, completion.session_id)
    end

    it "replays a repeated create carrying the same Idempotency-Key" do
      key = ::SecureRandom.uuid
      # An open-ended, high-temperature prompt makes content equality meaningful:
      # a non-deduplicated re-run would almost certainly differ.
      messages = [{role: "user", content: "Invent one surprising sentence about the sea. Be unpredictable."}]
      first = client.chat.create(messages: messages, idempotency_key: key, temperature: 1.3)
      second = client.chat.create(messages: messages, idempotency_key: key, temperature: 1.3)
      # The cached agent result is replayed, so the content is identical — yet the
      # dedup is otherwise transparent: the response id is regenerated per call.
      assert_equal(first.choices.first.message.content, second.choices.first.message.content)
      refute_equal(first.id, second.id, "expected the replayed completion to carry a freshly regenerated id")
    end
  end
end
