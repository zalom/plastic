# frozen_string_literal: true

require_relative "../../../varar/support/delivered_homes"

class SyncUpGraphArchiveRestoredTest < Minitest::Test
  include DeliveredHomes

  ARCHIVES = "SELECT intent_id, at, session_id, restored_at FROM archives"

  def archived(kernel)
    deliver(kernel)
    kernel.run!("intent", "archive", "1")
  end

  def test_a_restored_archive_survives_a_sync_up
    with_homes(method(:archived)) do |first, second|
      second.run!("sync", "up")
      first.run!("intent", "unarchive", "1")
      before = query(first, ARCHIVES)
      first.run!("sync", "up")

      assert_equal before, query(first, ARCHIVES)
      refute_nil before.first.last
    end
  end
end
