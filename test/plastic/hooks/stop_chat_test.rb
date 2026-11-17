# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/hooks/stop"

class StopChatTest < Plastic::TestCase
  include ConfigHomes

  fixtures :empty

  CLAUDE = { "CLAUDE_CODE_SESSION_ID" => "s-1" }.freeze
  REPLY = JSON.generate(last_assistant_message: "ready")

  def stop(input) = plastic("hook", "stop", input:, env: CLAUDE, table: Plastic::CLI::TABLE)

  def replies = store_graphs.databases.fetch(:local).rows("SELECT session_id, role, text FROM chat_messages")

  def test_full_chat_sync_records_the_reply
    seed_config(@plastic_home, "chat_sync: full\n")
    stop(REPLY)

    assert_equal [{ "session_id" => "s-1", "role" => "assistant", "text" => "ready" }], replies
  end

  def test_user_only_records_no_reply
    stop(REPLY)

    assert_empty replies
  end

  def test_a_stop_event_without_last_assistant_message_records_nothing
    seed_config(@plastic_home, "chat_sync: full\n")
    stop("{}")

    assert_empty replies
  end

  def hold_ready_work
    at = "2026-10-05T10:00:00+02:00"
    store_graphs.databases.fetch(:store).transaction do |batch|
      batch.put(:nodes, { intent_id: "1", id: "c", state: "claimed", claimed_by: "s-1", claimed_at: at, seen_at: at, updated_at: at })
      batch.put(:nodes, { intent_id: "1", id: "a", state: "open" })
    end
  end

  def refuse_chat_inserts = store_graphs.databases.fetch(:local).transaction { |batch| batch.add("CREATE TRIGGER refuse BEFORE INSERT ON chat_messages BEGIN SELECT RAISE(ABORT, 'write refused'); END") }

  def test_a_failed_chat_insert_does_not_change_the_decision_of_the_stop_gate
    seed_config(@plastic_home, "chat_sync: full\nrunner:\n  stop_hook: true\n")
    hold_ready_work
    refuse_chat_inserts
    result = stop(JSON.generate(last_assistant_message: "ready", stop_hook_active: false))

    assert_equal [0, true, true], [result.code, result.out.include?('"decision":"block"'), result.err.include?("write refused")]
  end
end
