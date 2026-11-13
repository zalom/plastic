# frozen_string_literal: true

require_relative "../../../varar/support/two_homes"

class SyncUpGraphClaimTest < Minitest::Test
  include TwoHomes

  def test_the_second_home_can_claim_the_next_node_of_the_graph
    with_two_homes do |_first, second|
      second.run!("sync", "up")

      assert_includes second.run!("node", "claim", "1", "n2").out, "n2"
    end
  end
end
