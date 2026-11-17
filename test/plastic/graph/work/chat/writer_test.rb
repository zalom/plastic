# frozen_string_literal: true

require_relative "../../../../test_helper"

class WorkChatWriterTest < Plastic::TestCase
  AT = Time.utc(2026, 11, 17, 9, 30, 0)

  def local = store_graphs.databases.fetch(:local)

  def writer(store: "plastic") = Plastic::Graph::Work::Chat::Writer.new(local, store:, clock: Struct.new(:now).new(AT))

  def rows = local.rows("SELECT session_id, harness, store, intent_id, role, at, text FROM chat_messages")

  def test_record_puts_one_row_with_the_clock_time
    writer.record(session_id: "s-1", harness: "codex", intent_id: "7", role: "user", text: "hello")

    assert_equal [{ "session_id" => "s-1", "harness" => "codex", "store" => "plastic", "intent_id" => "7", "role" => "user", "at" => Plastic.timestamp(AT), "text" => "hello" }], rows
  end

  def test_two_records_keep_two_rows_in_order
    writer.record(session_id: "s-1", harness: nil, intent_id: nil, role: "user", text: "one")
    writer.record(session_id: "s-1", harness: nil, intent_id: nil, role: "assistant", text: "two")

    assert_equal %w[one two], local.rows("SELECT text FROM chat_messages ORDER BY id").map { |row| row["text"] }
  end

  def test_role_outside_user_and_assistant_is_refused
    assert_raises(Plastic::Graph::Database::Error) do
      writer.record(session_id: "s-1", harness: nil, intent_id: nil, role: "system", text: "no")
    end
    assert_empty rows
  end
end
