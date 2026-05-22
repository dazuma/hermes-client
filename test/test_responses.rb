# frozen_string_literal: true

require "helper"

describe ::HermesAgent::Client::Entities::ResponseUsage do
  it "reads the token counts" do
    usage = ::HermesAgent::Client::Entities::ResponseUsage.new(
      "input_tokens" => 13_950, "output_tokens" => 3, "total_tokens" => 13_953
    )
    assert_equal(13_950, usage.input_tokens)
    assert_equal(3, usage.output_tokens)
    assert_equal(13_953, usage.total_tokens)
  end

  it "returns nil for fields when absent" do
    usage = ::HermesAgent::Client::Entities::ResponseUsage.new({})
    assert_nil(usage.input_tokens)
    assert_nil(usage.output_tokens)
    assert_nil(usage.total_tokens)
  end
end

describe ::HermesAgent::Client::Entities::ResponseContent do
  it "reads the type and text" do
    part = ::HermesAgent::Client::Entities::ResponseContent.new("type" => "output_text", "text" => "Hello there.")
    assert_equal("output_text", part.type)
    assert_equal("Hello there.", part.text)
  end

  it "returns nil for fields when absent" do
    part = ::HermesAgent::Client::Entities::ResponseContent.new({})
    assert_nil(part.type)
    assert_nil(part.text)
  end
end

describe ::HermesAgent::Client::Entities::ResponseOutputItem do
  let(:message_item) do
    {
      "type" => "message",
      "role" => "assistant",
      "content" => [{"type" => "output_text", "text" => "Hello there."}],
    }
  end
  let(:function_call_item) do
    {
      "type" => "function_call",
      "name" => "memory",
      "arguments" => '{"action": "add"}',
      "call_id" => "call_31079d214dc1",
    }
  end
  let(:function_call_output_item) do
    {
      "type" => "function_call_output",
      "call_id" => "call_31079d214dc1",
      "output" => '{"success": true}',
    }
  end

  it "reads a message item, wrapping content parts" do
    item = ::HermesAgent::Client::Entities::ResponseOutputItem.new(message_item)
    assert_equal("message", item.type)
    assert_equal("assistant", item.role)
    assert_kind_of(::Array, item.content)
    assert_instance_of(::HermesAgent::Client::Entities::ResponseContent, item.content.first)
    assert_equal("Hello there.", item.content.first.text)
  end

  it "exposes a message item's assembled text" do
    item = ::HermesAgent::Client::Entities::ResponseOutputItem.new(message_item)
    assert_equal("Hello there.", item.text)
  end

  it "reads a function_call item" do
    item = ::HermesAgent::Client::Entities::ResponseOutputItem.new(function_call_item)
    assert_equal("function_call", item.type)
    assert_equal("memory", item.name)
    assert_equal('{"action": "add"}', item.arguments)
    assert_equal("call_31079d214dc1", item.call_id)
  end

  it "reads a function_call_output item" do
    item = ::HermesAgent::Client::Entities::ResponseOutputItem.new(function_call_output_item)
    assert_equal("function_call_output", item.type)
    assert_equal("call_31079d214dc1", item.call_id)
    assert_equal('{"success": true}', item.output)
  end

  it "returns nil for fields when absent" do
    item = ::HermesAgent::Client::Entities::ResponseOutputItem.new({})
    assert_nil(item.type)
    assert_nil(item.role)
    assert_nil(item.content)
    assert_nil(item.name)
    assert_nil(item.arguments)
    assert_nil(item.call_id)
    assert_nil(item.output)
    assert_nil(item.text)
  end
end

describe ::HermesAgent::Client::Entities::Response do
  let(:payload) do
    {
      "id" => "resp_654553af158a4efeb3f92322242d",
      "object" => "response",
      "status" => "completed",
      "created_at" => 1_779_414_300,
      "model" => "hermes-test",
      "output" => [
        {
          "type" => "message",
          "role" => "assistant",
          "content" => [{"type" => "output_text", "text" => "Hello there."}],
        },
      ],
      "usage" => {"input_tokens" => 13_950, "output_tokens" => 3, "total_tokens" => 13_953},
    }
  end

  it "reads the scalar fields" do
    response = ::HermesAgent::Client::Entities::Response.new(payload)
    assert_equal("resp_654553af158a4efeb3f92322242d", response.id)
    assert_equal("response", response.object)
    assert_equal("completed", response.status)
    assert_equal(1_779_414_300, response.created_at)
    assert_equal("hermes-test", response.model)
  end

  it "wraps each output item in a ResponseOutputItem entity" do
    response = ::HermesAgent::Client::Entities::Response.new(payload)
    output = response.output
    assert_kind_of(::Array, output)
    assert_equal(1, output.length)
    assert_instance_of(::HermesAgent::Client::Entities::ResponseOutputItem, output.first)
    assert_equal("message", output.first.type)
  end

  it "wraps usage in a ResponseUsage entity" do
    response = ::HermesAgent::Client::Entities::Response.new(payload)
    assert_instance_of(::HermesAgent::Client::Entities::ResponseUsage, response.usage)
    assert_equal(13_953, response.usage.total_tokens)
  end

  it "aggregates the assistant text across message items as output_text" do
    response = ::HermesAgent::Client::Entities::Response.new(payload)
    assert_equal("Hello there.", response.output_text)
  end

  it "aggregates output_text only from message items, skipping tool items" do
    raw = payload.merge(
      "output" => [
        {"type" => "function_call", "name" => "memory", "arguments" => "{}", "call_id" => "c1"},
        {"type" => "message", "role" => "assistant",
         "content" => [{"type" => "output_text", "text" => "Done."}]},
      ]
    )
    response = ::HermesAgent::Client::Entities::Response.new(raw)
    assert_equal("Done.", response.output_text)
  end

  it "exposes the raw payload via to_h" do
    response = ::HermesAgent::Client::Entities::Response.new(payload)
    assert_equal("Hello there.", response.to_h["output"][0]["content"][0]["text"])
  end

  it "returns nil for fields when absent" do
    response = ::HermesAgent::Client::Entities::Response.new({})
    assert_nil(response.id)
    assert_nil(response.object)
    assert_nil(response.status)
    assert_nil(response.created_at)
    assert_nil(response.model)
    assert_nil(response.output)
    assert_nil(response.usage)
    assert_nil(response.output_text)
  end
end

describe ::HermesAgent::Client::Entities::ResponseDeletion do
  it "reads the id, object, and deleted flag" do
    deletion = ::HermesAgent::Client::Entities::ResponseDeletion.new(
      "id" => "resp_1", "object" => "response", "deleted" => true
    )
    assert_equal("resp_1", deletion.id)
    assert_equal("response", deletion.object)
    assert_equal(true, deletion.deleted?)
  end

  it "returns nil for fields when absent" do
    deletion = ::HermesAgent::Client::Entities::ResponseDeletion.new({})
    assert_nil(deletion.id)
    assert_nil(deletion.object)
    assert_nil(deletion.deleted?)
  end
end

describe ::HermesAgent::Client::Resources::Responses do
  let(:transport) do
    ::HermesAgent::Tests::FakeTransport.new("id" => "resp_1", "object" => "response")
  end

  it "posts to the /v1/responses path" do
    ::HermesAgent::Client::Resources::Responses.new(transport).create(input: "hello")
    assert_equal("/v1/responses", transport.requested_path)
  end

  it "sends the input in the request body" do
    ::HermesAgent::Client::Resources::Responses.new(transport).create(input: "hello")
    assert_equal("hello", transport.requested_body[:input])
  end

  it "does not send a model field" do
    ::HermesAgent::Client::Resources::Responses.new(transport).create(input: "hello")
    refute(transport.requested_body.key?(:model))
  end

  it "omits previous_response_id and conversation when not given" do
    ::HermesAgent::Client::Resources::Responses.new(transport).create(input: "hello")
    refute(transport.requested_body.key?(:previous_response_id))
    refute(transport.requested_body.key?(:conversation))
  end

  it "sends previous_response_id when chaining a prior turn" do
    ::HermesAgent::Client::Resources::Responses.new(transport).create(input: "hi", previous_response_id: "resp_0")
    assert_equal("resp_0", transport.requested_body[:previous_response_id])
  end

  it "sends a named conversation when given" do
    ::HermesAgent::Client::Resources::Responses.new(transport).create(input: "hi", conversation: "convo-1")
    assert_equal("convo-1", transport.requested_body[:conversation])
  end

  it "merges extra keyword arguments into the body" do
    ::HermesAgent::Client::Resources::Responses.new(transport).create(input: "hi", temperature: 0.2)
    assert_in_delta(0.2, transport.requested_body[:temperature])
  end

  it "wraps the create response in a Response entity" do
    response = ::HermesAgent::Client::Resources::Responses.new(transport).create(input: "hello")
    assert_instance_of(::HermesAgent::Client::Entities::Response, response)
    assert_equal("resp_1", response.id)
  end

  it "gets a response by id and wraps it in a Response entity" do
    response = ::HermesAgent::Client::Resources::Responses.new(transport).get("resp_1")
    assert_equal("/v1/responses/resp_1", transport.requested_path)
    assert_instance_of(::HermesAgent::Client::Entities::Response, response)
  end

  it "deletes a response by id and wraps the result in a ResponseDeletion entity" do
    deleter = ::HermesAgent::Tests::FakeTransport.new("id" => "resp_1", "object" => "response", "deleted" => true)
    deletion = ::HermesAgent::Client::Resources::Responses.new(deleter).delete("resp_1")
    assert_equal("/v1/responses/resp_1", deleter.requested_path)
    assert_instance_of(::HermesAgent::Client::Entities::ResponseDeletion, deletion)
    assert_equal(true, deletion.deleted?)
  end
end

describe "responses" do
  integration_port = ENV["HERMES_CLIENT_INTEGRATION_PORT"]

  if integration_port
    let(:client) do
      ::HermesAgent::Client.new(base_url: "http://localhost:#{integration_port}",
                                api_key: ::HermesAgent::Tests.integration_api_key)
    end

    # The last run of digits in a response's text (robust against the model
    # echoing an equation such as "7 + 5 = 12").
    def last_number(response)
      response.output_text.scan(/\d+/).last
    end

    it "creates, retrieves, and deletes a response against the live gateway" do
      response = client.responses.create(input: "Say hello in exactly two words.")
      assert_instance_of(::HermesAgent::Client::Entities::Response, response)
      assert_equal("response", response.object)
      assert_equal("completed", response.status)
      refute_empty(response.output_text)

      fetched = client.responses.get(response.id)
      assert_equal(response.id, fetched.id)
      assert_equal(response.output_text, fetched.output_text)

      deletion = client.responses.delete(response.id)
      assert_instance_of(::HermesAgent::Client::Entities::ResponseDeletion, deletion)
      assert_equal(true, deletion.deleted?)

      assert_raises(::HermesAgent::Client::NotFoundError) { client.responses.get(response.id) }
    end

    it "chains a follow-up turn via previous_response_id, carrying prior context" do
      first = client.responses.create(input: "Reply with only the number 7 and nothing else.")
      second = client.responses.create(
        input: "Add five to the number you just gave me. Reply with only the resulting number and nothing else.",
        previous_response_id: first.id
      )
      refute_equal(first.id, second.id)
      # The second turn could only produce 12 by knowing the prior turn's 7,
      # so a correct sum proves the conversation context chained.
      assert_equal("7", last_number(first))
      assert_equal("12", last_number(second))
    ensure
      client.responses.delete(first.id) if first
      client.responses.delete(second.id) if second
    end
  end
end
