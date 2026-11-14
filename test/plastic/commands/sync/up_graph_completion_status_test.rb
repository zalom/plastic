# frozen_string_literal: true

require_relative "../../../varar/support/delivered_homes"

class SyncUpGraphCompletionStatusTest < Minitest::Test
  include DeliveredHomes

  def test_a_delivered_intent_reads_done_and_delivered_on_a_second_home
    with_homes(method(:deliver)) do |_first, second|
      second.run!("sync", "up")

      assert_equal [["done", "delivered"]], query(second, "SELECT status, disposition FROM intents")
    end
  end
end
