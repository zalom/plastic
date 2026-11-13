# frozen_string_literal: true

require_relative "../../../varar/support/delivered_homes"

class SyncUpGraphArchiveRepeatTest < Minitest::Test
  include DeliveredHomes

  ARCHIVES = "SELECT intent_id, at, session_id, restored_at FROM archives"
  COMPLETION = "SELECT intent_id, at, session_id, judge, criteria, evidence, outcome_sha256 FROM completions"

  def archived(kernel)
    deliver(kernel)
    kernel.run!("intent", "archive", "1")
  end

  def rows_of(home) = [query(home, ARCHIVES), query(home, COMPLETION)]

  def test_a_delivered_archived_intent_arrives_with_its_completion_and_a_second_sync_up_changes_nothing
    with_homes(method(:archived)) do |first, second|
      second.run!("sync", "up")
      arrived = rows_of(second)
      index = second.read("store/index.json")

      refute_empty arrived.last
      assert_equal rows_of(first), arrived

      second.run!("sync", "up")

      assert_equal [arrived, index], [rows_of(second), second.read("store/index.json")]
    end
  end
end
