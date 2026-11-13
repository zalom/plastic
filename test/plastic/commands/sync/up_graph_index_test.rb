# frozen_string_literal: true

require_relative "../../../varar/support/two_homes"

class SyncUpGraphIndexTest < Minitest::Test
  include TwoHomes

  def test_the_index_after_the_move_equals_the_copied_one_except_for_origin_ids
    with_two_homes do |first, second|
      copied = unstamped(second.read("store/index.json"))
      second.run!("sync", "up")

      assert_equal copied, unstamped(second.read("store/index.json"))
      assert_equal unstamped(first.read("store/index.json")), unstamped(second.read("store/index.json"))
    end
  end

  def test_a_verdict_survives_the_move
    with_two_homes do |first, second|
      second.run!("sync", "up")
      sql = "SELECT round, verdict, findings FROM verdicts"

      refute_empty query(first, sql)
      assert_equal query(first, sql), query(second, sql)
    end
  end
end
