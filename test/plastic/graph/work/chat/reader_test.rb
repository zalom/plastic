# frozen_string_literal: true

require_relative "../../../../test_helper"

class WorkChatReaderTest < Plastic::TestCase
  def local = store_graphs.databases.fetch(:local)

  def record(store, at, text)
    clock = Struct.new(:now).new(at)
    Plastic::Graph::Work::Chat::Writer.new(local, store:, clock:).record(session_id: "s-1", harness: nil, intent_id: nil, role: "user", text:)
  end

  def test_orders_by_time_across_stores
    record("b", Time.utc(2026, 11, 17, 10), "second")
    record("a", Time.utc(2026, 11, 17, 9), "first")
    record(nil, Time.utc(2026, 11, 17, 11), "third")

    assert_equal %w[first second third], Plastic::Graph::Work::Chat::Reader.new(local).messages.map { |row| row["text"] }
  end

  def test_since_leaves_out_older_messages
    record("a", Time.utc(2026, 11, 16, 9), "old")
    record("a", Time.utc(2026, 11, 17, 9), "new")
    reader = Plastic::Graph::Work::Chat::Reader.new(local)

    assert_equal %w[new], reader.messages(since: Time.utc(2026, 11, 17)).map { |row| row["text"] }
  end
end
