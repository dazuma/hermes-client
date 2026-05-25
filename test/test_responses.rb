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
  # The streaming representation: output is an array of content parts, and the
  # item carries id/status (both absent in the non-streaming shape above).
  let(:streamed_function_call_output_item) do
    {
      "type" => "function_call_output",
      "id" => "fco_3256999d6a23446b920cb3d7",
      "status" => "completed",
      "call_id" => "call_31079d214dc1",
      "output" => [{"type" => "input_text", "text" => '{"exit_code": 0}'}],
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

  it "reads the id and status present on streamed output items" do
    item = ::HermesAgent::Client::Entities::ResponseOutputItem.new(streamed_function_call_output_item)
    assert_equal("fco_3256999d6a23446b920cb3d7", item.id)
    assert_equal("completed", item.status)
  end

  it "returns a non-streaming string output unchanged via output_text" do
    item = ::HermesAgent::Client::Entities::ResponseOutputItem.new(function_call_output_item)
    assert_equal('{"success": true}', item.output)
    assert_equal('{"success": true}', item.output_text)
  end

  it "normalizes a streaming array output to its JSON string via output_text" do
    item = ::HermesAgent::Client::Entities::ResponseOutputItem.new(streamed_function_call_output_item)
    assert_kind_of(::Array, item.output)
    assert_equal('{"exit_code": 0}', item.output_text)
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
    assert_nil(item.output_text)
    assert_nil(item.id)
    assert_nil(item.status)
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

describe ::HermesAgent::Client::Entities::ResponseStreamEvent do
  let(:created_event) do
    {
      "type" => "response.created",
      "response" => {"id" => "resp_1", "object" => "response", "status" => "in_progress"},
      "sequence_number" => 0,
    }
  end
  let(:item_added_event) do
    {
      "type" => "response.output_item.added",
      "output_index" => 0,
      "item" => {"id" => "msg_1", "type" => "message", "role" => "assistant", "content" => []},
      "sequence_number" => 1,
    }
  end
  let(:delta_event) do
    {
      "type" => "response.output_text.delta",
      "item_id" => "msg_1", "output_index" => 0, "content_index" => 0,
      "delta" => "ping", "sequence_number" => 2
    }
  end
  let(:done_event) do
    {
      "type" => "response.output_text.done",
      "item_id" => "msg_1", "output_index" => 0, "content_index" => 0,
      "text" => "ping", "sequence_number" => 3
    }
  end

  it "reads the type and sequence_number" do
    event = ::HermesAgent::Client::Entities::ResponseStreamEvent.new(created_event)
    assert_equal("response.created", event.type)
    assert_equal(0, event.sequence_number)
  end

  it "reads the incremental delta and threading fields on a delta event" do
    event = ::HermesAgent::Client::Entities::ResponseStreamEvent.new(delta_event)
    assert_equal("ping", event.delta)
    assert_equal("msg_1", event.item_id)
    assert_equal(0, event.output_index)
    assert_equal(0, event.content_index)
  end

  it "reads the assembled text on a done event" do
    event = ::HermesAgent::Client::Entities::ResponseStreamEvent.new(done_event)
    assert_equal("ping", event.text)
  end

  it "wraps the nested response object on a created/completed event" do
    event = ::HermesAgent::Client::Entities::ResponseStreamEvent.new(created_event)
    assert_instance_of(::HermesAgent::Client::Entities::Response, event.response)
    assert_equal("resp_1", event.response.id)
  end

  it "wraps the nested item object on an output_item event" do
    event = ::HermesAgent::Client::Entities::ResponseStreamEvent.new(item_added_event)
    assert_instance_of(::HermesAgent::Client::Entities::ResponseOutputItem, event.item)
    assert_equal("message", event.item.type)
  end

  it "returns nil for fields when absent" do
    event = ::HermesAgent::Client::Entities::ResponseStreamEvent.new({})
    assert_nil(event.type)
    assert_nil(event.sequence_number)
    assert_nil(event.delta)
    assert_nil(event.text)
    assert_nil(event.item_id)
    assert_nil(event.output_index)
    assert_nil(event.content_index)
    assert_nil(event.response)
    assert_nil(event.item)
  end
end

describe "Response session headers" do
  payload = {"id" => "resp_1", "object" => "response"}

  it "exposes session_id and session_key supplied from response headers" do
    response = ::HermesAgent::Client::Entities::Response.new(payload, session_id: "sid-1", session_key: "skey-1")
    assert_equal("sid-1", response.session_id)
    assert_equal("skey-1", response.session_key)
  end

  it "defaults the session readers to nil" do
    response = ::HermesAgent::Client::Entities::Response.new(payload)
    assert_nil(response.session_id)
    assert_nil(response.session_key)
  end

  it "keeps the session values out of the body payload (to_h)" do
    response = ::HermesAgent::Client::Entities::Response.new(payload, session_id: "sid-1", session_key: "skey-1")
    assert_equal(payload, response.to_h)
    refute(response.to_h.key?("session_id"))
  end

  it "factors the session values into equality and hash" do
    base = ::HermesAgent::Client::Entities::Response.new(payload, session_id: "s", session_key: "k")
    same = ::HermesAgent::Client::Entities::Response.new(payload, session_id: "s", session_key: "k")
    diff_id = ::HermesAgent::Client::Entities::Response.new(payload, session_id: "other", session_key: "k")
    body_only = ::HermesAgent::Client::Entities::Response.new(payload)
    assert_equal(base, same)
    assert_equal(base.hash, same.hash)
    refute_equal(base, diff_id)
    refute_equal(base, body_only)
  end
end

describe "Response.from_events" do
  let(:events) do
    [
      {"type" => "response.created",
       "response" => {"id" => "resp_1", "object" => "response", "status" => "in_progress", "output" => []},
       "sequence_number" => 0},
      {"type" => "response.output_text.delta", "delta" => "ping", "sequence_number" => 2},
      {"type" => "response.completed",
       "response" => {"id" => "resp_1", "object" => "response", "status" => "completed",
                      "output" => [{"type" => "message", "role" => "assistant",
                                    "content" => [{"type" => "output_text", "text" => "ping"}]}],
                      "usage" => {"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2}},
       "sequence_number" => 5},
    ].map { |hash| ::HermesAgent::Client::Entities::ResponseStreamEvent.new(hash) }
  end

  it "takes the final response object from the terminal response.completed event" do
    response = ::HermesAgent::Client::Entities::Response.from_events(events)
    assert_instance_of(::HermesAgent::Client::Entities::Response, response)
    assert_equal("resp_1", response.id)
    assert_equal("completed", response.status)
    assert_equal("ping", response.output_text)
    assert_equal(2, response.usage.total_tokens)
  end

  it "returns a Response wrapping an empty payload when no event carried a response" do
    bare = [::HermesAgent::Client::Entities::ResponseStreamEvent.new("type" => "response.output_text.delta")]
    response = ::HermesAgent::Client::Entities::Response.from_events(bare)
    assert_instance_of(::HermesAgent::Client::Entities::Response, response)
    assert_nil(response.id)
  end

  it "carries session headers passed to it onto the assembled response" do
    response = ::HermesAgent::Client::Entities::Response.from_events(events, session_id: "sid-1", session_key: "skey-1")
    assert_equal("sid-1", response.session_id)
    assert_equal("skey-1", response.session_key)
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

  it "sends the idempotency_key as an Idempotency-Key request header" do
    ::HermesAgent::Client::Resources::Responses.new(transport).create(input: "hi", idempotency_key: "abc-123")
    assert_equal("abc-123", transport.requested_headers["Idempotency-Key"])
  end

  it "gets a response by id and wraps it in a Response entity" do
    response = ::HermesAgent::Client::Resources::Responses.new(transport).get("resp_1")
    assert_equal("/v1/responses/resp_1", transport.requested_path)
    assert_instance_of(::HermesAgent::Client::Entities::Response, response)
  end

  it "reads the response session headers onto the created response" do
    sourced = ::HermesAgent::Tests::FakeTransport.new(
      {"id" => "resp_1", "object" => "response"}, [], {"x-hermes-session-id" => "sid-3"}
    )
    response = ::HermesAgent::Client::Resources::Responses.new(sourced).create(input: "hi")
    assert_equal("sid-3", response.session_id)
    assert_nil(response.session_key)
  end

  it "does not send session request headers (responses ignores them)" do
    ::HermesAgent::Client::Resources::Responses.new(transport).create(input: "hi")
    assert(transport.requested_headers.nil? || transport.requested_headers.empty?)
  end

  it "leaves session readers nil on a retrieved response (GET returns no session headers)" do
    response = ::HermesAgent::Client::Resources::Responses.new(transport).get("resp_1")
    assert_nil(response.session_id)
    assert_nil(response.session_key)
  end

  it "deletes a response by id and wraps the result in a ResponseDeletion entity" do
    deleter = ::HermesAgent::Tests::FakeTransport.new("id" => "resp_1", "object" => "response", "deleted" => true)
    deletion = ::HermesAgent::Client::Resources::Responses.new(deleter).delete("resp_1")
    assert_equal("/v1/responses/resp_1", deleter.requested_path)
    assert_instance_of(::HermesAgent::Client::Entities::ResponseDeletion, deletion)
    assert_equal(true, deletion.deleted?)
  end
end

describe "Resources::Responses#stream_create" do
  def frame(hash)
    "event: #{hash['type']}\ndata: #{::JSON.generate(hash)}\n\n"
  end

  let(:stream_chunks) do
    [
      frame("type" => "response.created",
            "response" => {"id" => "resp_1", "object" => "response", "status" => "in_progress", "output" => []},
            "sequence_number" => 0),
      frame("type" => "response.output_text.delta", "item_id" => "msg_1", "delta" => "Hello", "sequence_number" => 2),
      frame("type" => "response.output_text.delta", "item_id" => "msg_1", "delta" => " world", "sequence_number" => 3),
      frame("type" => "response.completed",
            "response" => {"id" => "resp_1", "object" => "response", "status" => "completed",
                           "output" => [{"type" => "message", "role" => "assistant",
                                         "content" => [{"type" => "output_text", "text" => "Hello world"}]}],
                           "usage" => {"input_tokens" => 1, "output_tokens" => 2, "total_tokens" => 3}},
            "sequence_number" => 5),
    ]
  end
  let(:transport) { ::HermesAgent::Tests::FakeTransport.new({}, stream_chunks) }

  it "posts to /v1/responses with stream enabled and the input" do
    ::HermesAgent::Client::Resources::Responses.new(transport).stream_create(input: "hi").result
    assert_equal("/v1/responses", transport.requested_path)
    assert_equal("hi", transport.requested_body[:input])
    assert_equal(true, transport.requested_body[:stream])
  end

  it "sends previous_response_id and conversation when chaining" do
    resource = ::HermesAgent::Client::Resources::Responses.new(transport)
    resource.stream_create(input: "hi", previous_response_id: "resp_0", conversation: "c1").result
    assert_equal("resp_0", transport.requested_body[:previous_response_id])
    assert_equal("c1", transport.requested_body[:conversation])
  end

  it "carries response session headers onto the assembled response" do
    sourced = ::HermesAgent::Tests::FakeTransport.new({}, stream_chunks, {"x-hermes-session-id" => "sid-s"})
    response = ::HermesAgent::Client::Resources::Responses.new(sourced).stream_create(input: "hi").result
    assert_equal("sid-s", response.session_id)
  end

  it "yields ResponseStreamEvent events and returns the assembled Response (block form)" do
    deltas = []
    response = ::HermesAgent::Client::Resources::Responses.new(transport).stream_create(input: "hi") do |event|
      assert_instance_of(::HermesAgent::Client::Entities::ResponseStreamEvent, event)
      deltas << event.delta if event.delta
    end
    assert_equal(["Hello", " world"], deltas)
    assert_instance_of(::HermesAgent::Client::Entities::Response, response)
    assert_equal("Hello world", response.output_text)
    assert_equal(3, response.usage.total_tokens)
  end

  it "returns a Stream the caller can iterate (enumerator form)" do
    stream = ::HermesAgent::Client::Resources::Responses.new(transport).stream_create(input: "hi")
    assert_instance_of(::HermesAgent::Client::Stream, stream)
    text = stream.each.filter_map(&:delta).join
    assert_equal("Hello world", text)
    assert_equal("Hello world", stream.result.output_text)
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

    it "streams a response turn against the live gateway" do
      deltas = []
      response = client.responses.stream_create(input: "Count: one two three") do |event|
        assert_instance_of(::HermesAgent::Client::Entities::ResponseStreamEvent, event)
        deltas << event.delta if event.delta
      end
      assert_instance_of(::HermesAgent::Client::Entities::Response, response)
      streamed_text = deltas.join
      refute_empty(streamed_text)
      assert_equal(streamed_text, response.output_text)
    ensure
      client.responses.delete(response.id) if response&.id
    end

    it "surfaces function-call items with id/status/output_text on a tool-executing stream" do
      # The `date` command runs a single fast tool, unlike a directory listing
      # (which triggers a slow, timeout-prone search_files scan).
      prompt = "Please run the shell command 'date' in the terminal and tell me the output."
      call_outputs = []
      response = client.responses.stream_create(input: prompt) do |event|
        item = event.item
        call_outputs << item if item && item.type == "function_call_output"
      end

      refute_empty(call_outputs, "expected a function_call_output item in the stream")
      output_item = call_outputs.first
      refute_nil(output_item.id, "streamed items carry an id")
      refute_nil(output_item.status)
      refute_nil(output_item.call_id)
      refute_empty(output_item.output_text)

      # The assembled response includes the tool items and the final message text.
      assert_instance_of(::HermesAgent::Client::Entities::Response, response)
      types = response.output.map(&:type)
      assert_includes(types, "function_call")
      assert_includes(types, "function_call_output")
      refute_empty(response.output_text)
    ensure
      client.responses.delete(response.id) if response&.id
    end

    it "replays a repeated create carrying the same Idempotency-Key" do
      key = ::SecureRandom.uuid
      # An open-ended, high-temperature prompt makes content equality meaningful:
      # a non-deduplicated re-run would almost certainly differ.
      input = "Invent one surprising sentence about a mountain. Be unpredictable."
      first = client.responses.create(input: input, idempotency_key: key, temperature: 1.3)
      second = client.responses.create(input: input, idempotency_key: key, temperature: 1.3)
      # The cached agent result is replayed, so the text is identical — yet the
      # dedup is otherwise transparent: a fresh response id is minted per call.
      assert_equal(first.output_text, second.output_text)
      refute_equal(first.id, second.id, "expected the replayed response to carry a freshly regenerated id")
    ensure
      client.responses.delete(first.id) if first&.id
      client.responses.delete(second.id) if second&.id
    end
  end
end
