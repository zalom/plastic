# frozen_string_literal: true

require_relative "../../../varar/support/two_homes"

class SyncUpGraphSurvivalTest < Minitest::Test
  include TwoHomes

  def test_findings_that_hold_id_and_intent_id_survive_the_move_unchanged
    with_two_homes do |_first, second|
      second.run!("sync", "up")

      assert_equal ["The test is red for the right reason; see :id and :intent_id"], query(second, "SELECT findings FROM nodes WHERE id = 'n1'").flatten
    end
  end
end
