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
end
