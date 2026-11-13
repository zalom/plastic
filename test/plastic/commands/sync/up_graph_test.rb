# frozen_string_literal: true

require_relative "../../../varar/support/two_homes"

class SyncUpGraphTest < Minitest::Test
  include TwoHomes

  def test_the_nodes_of_one_machine_continue_on_a_second_home_after_sync_up
    with_two_homes do |first, second|
      second.run!("sync", "up")

      assert_equal nodes(first), nodes(second)
      assert_equal [second.origin], query(second, "SELECT DISTINCT origin_id FROM nodes").flatten
    end
  end

  def test_the_edges_approval_and_status_of_one_machine_continue_on_a_second_home
    with_two_homes do |first, second|
      second.run!("sync", "up")
      sql = ["SELECT count(*) FROM edges", "SELECT count(*) FROM approvals", "SELECT status FROM intents"]

      assert_equal sql.map { |text| query(first, text) }, sql.map { |text| query(second, text) }
    end
  end
end
