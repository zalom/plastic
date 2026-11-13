# frozen_string_literal: true

require_relative "../../../varar/support/two_homes"

class SyncUpGraphViewsTest < Minitest::Test
  include TwoHomes

  def test_graph_show_and_graph_resume_say_the_same_in_both_homes
    with_two_homes do |first, second|
      second.run!("sync", "up")

      assert_equal first.run!("graph", "show", "1").out, second.run!("graph", "show", "1").out
      assert_equal first.run!("graph", "resume").out, second.run!("graph", "resume").out
    end
  end

  def test_sync_down_after_the_move_writes_nothing_and_exits_zero
    with_two_homes do |first, second|
      second.run!("sync", "up")
      call = second.run("sync", "down")

      assert_equal [0, "none"], [call.code, call.files]
      assert_equal first.read(GRAPH), second.read(GRAPH)
    end
  end
end
