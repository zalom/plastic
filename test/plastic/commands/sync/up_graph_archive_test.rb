# frozen_string_literal: true

require_relative "../../../varar/support/delivered_homes"

class SyncUpGraphArchiveTest < Minitest::Test
  include DeliveredHomes

  COMPLETION = "SELECT intent_id, at, session_id, judge, criteria, evidence, outcome_sha256 FROM completions"
  ARCHIVES = "SELECT intent_id, at, session_id, restored_at FROM archives"

  def archived(kernel)
    deliver(kernel)
    kernel.run!("intent", "archive", "1")
  end

  def seen_from(home) = [query(home, ARCHIVES), query(home, "SELECT status, disposition FROM intents"), query(home, COMPLETION), unstamped(home.read("store/index.json"))]

  def test_an_archived_intent_reads_archived_with_its_status_completion_and_index_on_a_second_home
    with_homes(method(:archived)) do |first, second|
      second.run!("sync", "up")

      assert_equal seen_from(first), seen_from(second)
      assert_equal [["1", nil]], query(second, "SELECT intent_id, restored_at FROM archives")
    end
  end
end
