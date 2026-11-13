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

  def test_a_second_sync_up_changes_nothing
    with_homes(method(:archived)) do |_first, second|
      second.run!("sync", "up")
      before = [query(second, ARCHIVES), query(second, COMPLETION), second.read("store/index.json")]
      second.run!("sync", "up")

      assert_equal before, [query(second, ARCHIVES), query(second, COMPLETION), second.read("store/index.json")]
    end
  end
end
