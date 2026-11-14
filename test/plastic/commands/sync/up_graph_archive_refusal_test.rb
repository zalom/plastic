# frozen_string_literal: true

require_relative "../../../varar/support/delivered_homes"

class SyncUpGraphArchiveRefusalTest < Minitest::Test
  include DeliveredHomes

  def archived(kernel)
    deliver(kernel)
    kernel.run!("intent", "archive", "1")
  end

  def test_unarchive_on_the_second_home_refuses_and_leaves_the_archive_mark
    with_homes(method(:archived)) do |_first, second|
      second.run!("sync", "up")
      call = second.run("intent", "unarchive", "1")

      assert_equal [1, [[nil]], false], [call.code, query(second, "SELECT restored_at FROM archives"), File.exist?(second.path(DIR))]
      assert_match(/snapshot is on the first home/, call.reason)
    end
  end
end
