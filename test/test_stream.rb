# frozen_string_literal: true

require "helper"

# A distinct Entity subclass so dispatch-by-event-name can be asserted by class.
class NamedStreamEvent < ::HermesAgent::Client::Entity; end

describe ::HermesAgent::Client::Stream do
  # Build a stream over a fixed array of byte chunks, wrapping each frame's
  # data in the base Entity so the parser can be exercised in isolation.
  def build(chunks, terminator: nil, &aggregator)
    ::HermesAgent::Client::Stream.new(
      chunks, event_class: ::HermesAgent::Client::Entity, terminator: terminator, &aggregator
    )
  end

  it "yields one event per SSE frame with parsed JSON data" do
    seen = build(["data: {\"n\":1}\n\n", "data: {\"n\":2}\n\n"]).map { |event| event["n"] }
    assert_equal([1, 2], seen)
  end

  it "reassembles frames split across chunk boundaries" do
    chunks = ["data: {\"n\":", "1}\n", "\n", "data: {\"n\":2}\n\n"]
    seen = build(chunks).map { |event| event["n"] }
    assert_equal([1, 2], seen)
  end

  it "handles CRLF line endings" do
    seen = build(["data: {\"n\":1}\r\n\r\n"]).map { |event| event["n"] }
    assert_equal([1], seen)
  end

  it "ignores comment lines" do
    seen = build([": keep-alive\n\n", "data: {\"n\":1}\n\n"]).map { |event| event["n"] }
    assert_equal([1], seen)
  end

  it "joins multiple data lines in a frame with newlines" do
    # The two data lines join to "[1,\n2]", which parses as the array [1, 2].
    seen = nil
    build(["data: [1,\ndata: 2]\n\n"]).each { |event| seen = event.to_h }
    assert_equal([1, 2], seen)
  end

  it "wraps each event in the given event_class" do
    seen = nil
    build(["data: {\"n\":1}\n\n"]).each { |event| seen = event }
    assert_instance_of(::HermesAgent::Client::Entity, seen)
  end

  it "dispatches each frame to the class a callable event_class chooses from the event name" do
    resolver = ->(name) { name == "tool" ? NamedStreamEvent : ::HermesAgent::Client::Entity }
    chunks = ["data: {\"n\":1}\n\n", "event: tool\ndata: {\"n\":2}\n\n"]
    seen = ::HermesAgent::Client::Stream.new(chunks, event_class: resolver).to_a
    assert_instance_of(::HermesAgent::Client::Entity, seen[0])
    assert_instance_of(NamedStreamEvent, seen[1])
    assert_equal([1, 2], seen.map { |event| event["n"] })
  end

  it "passes nil to the resolver for an unnamed frame" do
    names = []
    resolver = lambda do |name|
      names << name
      ::HermesAgent::Client::Entity
    end
    ::HermesAgent::Client::Stream.new(["data: {\"n\":1}\n\n"], event_class: resolver).to_a
    assert_equal([nil], names)
  end

  it "does not leak an event name from one frame into the next" do
    resolver = ->(name) { name == "tool" ? NamedStreamEvent : ::HermesAgent::Client::Entity }
    chunks = ["event: tool\ndata: {\"n\":1}\n\n", "data: {\"n\":2}\n\n"]
    seen = ::HermesAgent::Client::Stream.new(chunks, event_class: resolver).to_a
    assert_instance_of(NamedStreamEvent, seen[0])
    assert_instance_of(::HermesAgent::Client::Entity, seen[1])
  end

  it "applies a plain Class event_class to every frame, ignoring the event name" do
    chunks = ["event: anything\ndata: {\"n\":1}\n\n", "data: {\"n\":2}\n\n"]
    seen = build(chunks).to_a
    assert(seen.all? { |event| event.instance_of?(::HermesAgent::Client::Entity) })
    assert_equal([1, 2], seen.map { |event| event["n"] })
  end

  it "does not yield the terminator frame" do
    seen = build(["data: {\"n\":1}\n\n", "data: [DONE]\n\n"], terminator: "[DONE]").map { |event| event["n"] }
    assert_equal([1], seen)
  end

  it "maps a malformed JSON frame to MalformedResponseError" do
    error = assert_raises(::HermesAgent::Client::MalformedResponseError) do
      build(["data: not json{\n\n"]).each { |_event| nil }
    end
    assert_equal("not json{", error.body)
  end

  it "is Enumerable when called without a block" do
    stream = build(["data: {\"n\":1}\n\n", "data: {\"n\":2}\n\n"])
    assert_kind_of(::Enumerable, stream)
    assert_equal([1, 2], stream.each.map { |event| event["n"] })
  end

  it "exposes the aggregated result after iterating" do
    stream = build(["data: {\"n\":1}\n\n", "data: {\"n\":2}\n\n"]) { |events| events.sum { |e| e["n"] } }
    stream.each { |_event| nil }
    assert_equal(3, stream.result)
  end

  it "drains the stream when result is requested without iterating" do
    stream = build(["data: {\"n\":5}\n\n"]) { |events| events.sum { |e| e["n"] } }
    assert_equal(5, stream.result)
  end
end
