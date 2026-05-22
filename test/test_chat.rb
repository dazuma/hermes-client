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
  end
end
