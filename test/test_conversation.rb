# frozen_string_literal: true

require "helper"

# A transport double that returns a fresh response id per request and records
# every request body, so multi-turn chaining can be asserted across turns.
class RecordingTransport
  def initialize(ids = [])
    @ids = ids
    @index = 0
    @bodies = []
  end

  # The request bodies seen, in order.
  attr_reader :bodies

  def post(_path, body)
    @bodies << body
    id = @ids[@index] || "resp_auto_#{@index}"
    @index += 1
    ::HermesAgent::Client::Transport::Result.new(body: {"id" => id, "object" => "response"}, headers: {})
  end
end

describe ::HermesAgent::Client::Conversation do
  let(:responses) do
    ::HermesAgent::Client::Resources::Responses.new(
      ::HermesAgent::Tests::FakeTransport.new("id" => "resp_1", "object" => "response")
    )
  end

  describe "construction" do
    it "rejects supplying both a name and a previous_response_id" do
      assert_raises(::ArgumentError) do
        ::HermesAgent::Client::Conversation.new(responses, name: "c", previous_response_id: "resp_0")
      end
    end
  end

  describe "id-tracking mode" do
    it "sends no chaining fields on the first turn" do
      transport = RecordingTransport.new(["resp_1"])
      convo = ::HermesAgent::Client::Conversation.new(
        ::HermesAgent::Client::Resources::Responses.new(transport)
      )
      convo.create(input: "hello")
      refute(transport.bodies[0].key?(:previous_response_id))
      refute(transport.bodies[0].key?(:conversation))
    end

    it "captures the response id as last_response_id" do
      convo = ::HermesAgent::Client::Conversation.new(responses)
      convo.create(input: "hello")
      assert_equal("resp_1", convo.last_response_id)
    end

    it "returns the Response entity from create" do
      convo = ::HermesAgent::Client::Conversation.new(responses)
      response = convo.create(input: "hello")
      assert_instance_of(::HermesAgent::Client::Entities::Response, response)
      assert_equal("resp_1", response.id)
    end

    it "chains the prior turn's id as previous_response_id on the next turn" do
      transport = RecordingTransport.new(["resp_1", "resp_2"])
      convo = ::HermesAgent::Client::Conversation.new(
        ::HermesAgent::Client::Resources::Responses.new(transport)
      )
      convo.create(input: "first")
      convo.create(input: "second")
      assert_equal("resp_1", transport.bodies[1][:previous_response_id])
    end

    it "advances the chain to the most recent id across several turns" do
      transport = RecordingTransport.new(["resp_1", "resp_2", "resp_3"])
      convo = ::HermesAgent::Client::Conversation.new(
        ::HermesAgent::Client::Resources::Responses.new(transport)
      )
      convo.create(input: "first")
      convo.create(input: "second")
      convo.create(input: "third")
      assert_equal("resp_2", transport.bodies[2][:previous_response_id])
      assert_equal("resp_3", convo.last_response_id)
    end

    it "seeds the chain from a previous_response_id given at construction" do
      transport = RecordingTransport.new(["resp_9"])
      convo = ::HermesAgent::Client::Conversation.new(
        ::HermesAgent::Client::Resources::Responses.new(transport), previous_response_id: "resp_seed"
      )
      convo.create(input: "resume")
      assert_equal("resp_seed", transport.bodies[0][:previous_response_id])
    end

    it "merges extra keyword arguments into the body" do
      transport = RecordingTransport.new(["resp_1"])
      convo = ::HermesAgent::Client::Conversation.new(
        ::HermesAgent::Client::Resources::Responses.new(transport)
      )
      convo.create(input: "hi", temperature: 0.2)
      assert_in_delta(0.2, transport.bodies[0][:temperature])
    end
  end

  describe "named mode" do
    it "sends the conversation name on every turn and never previous_response_id" do
      transport = RecordingTransport.new(["resp_1", "resp_2"])
      convo = ::HermesAgent::Client::Conversation.new(
        ::HermesAgent::Client::Resources::Responses.new(transport), name: "support-42"
      )
      convo.create(input: "first")
      convo.create(input: "second")
      assert_equal("support-42", transport.bodies[0][:conversation])
      assert_equal("support-42", transport.bodies[1][:conversation])
      refute(transport.bodies[1].key?(:previous_response_id))
    end

    it "exposes the conversation name" do
      convo = ::HermesAgent::Client::Conversation.new(responses, name: "support-42")
      assert_equal("support-42", convo.name)
    end

    it "still records last_response_id for inspection" do
      convo = ::HermesAgent::Client::Conversation.new(responses, name: "support-42")
      convo.create(input: "hello")
      assert_equal("resp_1", convo.last_response_id)
    end
  end

  describe "streaming" do
    def frame(hash)
      "event: #{hash['type']}\ndata: #{::JSON.generate(hash)}\n\n"
    end

    let(:stream_chunks) do
      [
        frame("type" => "response.created",
              "response" => {"id" => "resp_s1", "object" => "response", "status" => "in_progress", "output" => []},
              "sequence_number" => 0),
        frame("type" => "response.output_text.delta", "item_id" => "msg_1", "delta" => "Hi", "sequence_number" => 2),
        frame("type" => "response.completed",
              "response" => {"id" => "resp_s1", "object" => "response", "status" => "completed",
                             "output" => [{"type" => "message", "role" => "assistant",
                                           "content" => [{"type" => "output_text", "text" => "Hi"}]}],
                             "usage" => {"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2}},
              "sequence_number" => 5),
      ]
    end
    let(:transport) { ::HermesAgent::Tests::FakeTransport.new({}, stream_chunks) }
    let(:convo) do
      ::HermesAgent::Client::Conversation.new(::HermesAgent::Client::Resources::Responses.new(transport))
    end

    it "yields events and returns the assembled Response (block form)" do
      deltas = []
      response = convo.stream_create(input: "hi") do |event|
        deltas << event.delta if event.delta
      end
      assert_equal(["Hi"], deltas)
      assert_instance_of(::HermesAgent::Client::Entities::Response, response)
      assert_equal("Hi", response.output_text)
    end

    it "captures last_response_id after the block-form stream completes" do
      convo.stream_create(input: "hi") { |_event| nil }
      assert_equal("resp_s1", convo.last_response_id)
    end

    it "returns a Stream in the enumerator form" do
      stream = convo.stream_create(input: "hi")
      assert_instance_of(::HermesAgent::Client::Stream, stream)
    end

    it "captures last_response_id once the enumerator-form stream is consumed" do
      stream = convo.stream_create(input: "hi")
      assert_nil(convo.last_response_id)
      stream.each { |_event| nil }
      assert_equal("resp_s1", convo.last_response_id)
    end

    it "chains a follow-up create onto the streamed turn's id" do
      recording = RecordingTransport.new
      streaming = ::HermesAgent::Tests::FakeTransport.new({}, stream_chunks)
      # Stream first (FakeTransport-backed resource), then create on a recorder
      # to inspect the chaining the streamed id produced.
      stream_convo = ::HermesAgent::Client::Conversation.new(
        ::HermesAgent::Client::Resources::Responses.new(streaming)
      )
      stream_convo.stream_create(input: "hi").result
      # Re-create against the recorder seeded with the captured id.
      seeded = ::HermesAgent::Client::Conversation.new(
        ::HermesAgent::Client::Resources::Responses.new(recording),
        previous_response_id: stream_convo.last_response_id
      )
      seeded.create(input: "next")
      assert_equal("resp_s1", recording.bodies[0][:previous_response_id])
    end

    it "sends the conversation name on a streamed named-mode turn" do
      named = ::HermesAgent::Client::Conversation.new(
        ::HermesAgent::Client::Resources::Responses.new(transport), name: "c-stream"
      )
      named.stream_create(input: "hi").result
      assert_equal("c-stream", transport.requested_body[:conversation])
    end
  end
end

describe "Resources::Responses#conversation" do
  let(:responses) do
    ::HermesAgent::Client::Resources::Responses.new(
      ::HermesAgent::Tests::FakeTransport.new("id" => "resp_1", "object" => "response")
    )
  end

  it "returns a Conversation" do
    assert_instance_of(::HermesAgent::Client::Conversation, responses.conversation)
  end

  it "builds a named conversation when given a name" do
    convo = responses.conversation(name: "c1")
    assert_equal("c1", convo.name)
  end

  it "seeds an id-tracking conversation from a previous_response_id" do
    transport = RecordingTransport.new(["resp_x"])
    convo = ::HermesAgent::Client::Resources::Responses.new(transport).conversation(previous_response_id: "resp_seed")
    convo.create(input: "hi")
    assert_equal("resp_seed", transport.bodies[0][:previous_response_id])
  end
end

describe "conversation chaining" do
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

    it "auto-threads previous_response_id across turns via the helper" do
      convo = client.responses.conversation
      first = convo.create(input: "Reply with only the number 7 and nothing else.")
      second = convo.create(
        input: "Add five to the number you just gave me. Reply with only the resulting number and nothing else."
      )
      refute_equal(first.id, second.id)
      assert_equal(second.id, convo.last_response_id)
      # A correct sum (12) is only possible if the prior turn's 7 chained in.
      assert_equal("7", last_number(first))
      assert_equal("12", last_number(second))
    ensure
      client.responses.delete(first.id) if first
      client.responses.delete(second.id) if second
    end
  end
end
