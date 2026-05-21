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
  end
end
