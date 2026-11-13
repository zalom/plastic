# frozen_string_literal: true

require_relative "../../../varar/support/two_homes"

class SyncUpGraphRepeatTest < Minitest::Test
  include TwoHomes

  def test_a_second_sync_up_leaves_graph_json_and_its_printed_hash_as_they_are
    with_two_homes do |first, second|
      second.run!("sync", "up")
      bytes = second.read(GRAPH)
      printed = second.rows("work_graph.db", "SELECT sha256 FROM printed WHERE path = '#{GRAPH}'")
      second.run!("sync", "up")

      assert_equal bytes, first.read(GRAPH)
      assert_equal [bytes, printed], [second.read(GRAPH), second.rows("work_graph.db", "SELECT sha256 FROM printed WHERE path = '#{GRAPH}'")]
    end
  end
end
