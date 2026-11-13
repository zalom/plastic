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

  def test_a_delivered_archived_intent_arrives_with_its_completion_and_a_second_sync_up_changes_nothing
    with_homes(method(:archived)) do |first, second|
      second.run!("sync", "up")
      before = [query(second, ARCHIVES), query(second, COMPLETION), second.read("store/index.json")]

      refute_empty before[1]
      assert_equal [query(first, ARCHIVES), query(first, COMPLETION)], before.first(2)

      second.run!("sync", "up")

      assert_equal before, [query(second, ARCHIVES), query(second, COMPLETION), second.read("store/index.json")]
    end
  end
end
