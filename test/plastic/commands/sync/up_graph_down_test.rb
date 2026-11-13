# frozen_string_literal: true

require_relative "../../../varar/support/two_homes"

class SyncUpGraphDownTest < Minitest::Test
  include TwoHomes

  def test_sync_down_after_the_move_writes_nothing_and_exits_zero
    with_two_homes do |first, second|
      second.run!("sync", "up")
      call = second.run("sync", "down")

      assert_equal [0, "none"], [call.code, call.files]
      assert_equal first.read(GRAPH), second.read(GRAPH)
    end
  end
end
