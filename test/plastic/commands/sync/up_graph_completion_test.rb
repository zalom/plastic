# frozen_string_literal: true

require_relative "../../../varar/support/delivered_homes"

class SyncUpGraphCompletionTest < Minitest::Test
  include DeliveredHomes

  COMPLETION = "SELECT intent_id, at, session_id, judge, criteria, evidence, outcome_sha256 FROM completions"

  def test_the_completion_of_a_delivered_intent_continues_on_a_second_home
    with_homes(method(:deliver)) do |first, second|
      second.run!("sync", "up")

      refute_empty query(first, COMPLETION)
      assert_equal query(first, COMPLETION), query(second, COMPLETION)
      assert_equal [second.origin], query(second, "SELECT origin_id FROM completions").flatten
    end
  end
end
