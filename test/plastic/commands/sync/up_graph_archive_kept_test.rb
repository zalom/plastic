# frozen_string_literal: true

require_relative "../../../varar/support/delivered_homes"

class SyncUpGraphArchiveKeptTest < Minitest::Test
  include DeliveredHomes

  def kept(kernel)
    kernel.run!("intent", "new", "Waiting", "--status", "parked", "--reason", "Waiting for the supplier")
    kernel.run!("intent", "new", "Dropped")
    abandon(kernel, "3")
  end

  def test_a_parked_and_an_abandoned_intent_keep_their_reason_and_disposition_on_a_second_home
    with_homes(method(:kept)) do |first, second|
      second.run!("sync", "up")
      sql = "SELECT intent_id, status, disposition, reason FROM intents ORDER BY intent_id"

      assert_includes query(second, sql), ["2", "parked", nil, "Waiting for the supplier"]
      assert_equal query(first, sql), query(second, sql)
    end
  end
end
