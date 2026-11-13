# frozen_string_literal: true

require_relative "../../../varar/support/delivered_homes"

class SyncUpGraphArchiveTest < Minitest::Test
  include DeliveredHomes

  COMPLETION = "SELECT intent_id, at, session_id, judge, criteria, evidence, outcome_sha256 FROM completions"
  ARCHIVES = "SELECT intent_id, at, session_id, restored_at FROM archives"

  def archived(kernel)
    deliver(kernel)
    kernel.run!("intent", "archive", "1")
  end

  def kept(kernel)
    kernel.run!("intent", "new", "Waiting", "--status", "parked", "--reason", "Waiting for the supplier")
    kernel.run!("intent", "new", "Dropped")
    abandon(kernel, "3")
  end

  def test_an_archived_intent_reads_archived_on_a_second_home
    with_homes(method(:archived)) do |first, second|
      second.run!("sync", "up")

      assert_equal [["1", nil]], query(second, "SELECT intent_id, restored_at FROM archives")
      assert_equal query(first, ARCHIVES), query(second, ARCHIVES)
    end
  end

  def test_an_archived_intent_keeps_its_status_and_completion_on_a_second_home
    with_homes(method(:archived)) do |first, second|
      second.run!("sync", "up")

      assert_equal [["done", "delivered"]], query(second, "SELECT status, disposition FROM intents")
      assert_equal query(first, COMPLETION), query(second, COMPLETION)
    end
  end

  def test_the_index_of_the_second_home_equals_the_index_of_the_first
    with_homes(method(:archived)) do |first, second|
      second.run!("sync", "up")

      assert_equal unstamped(first.read("store/index.json")), unstamped(second.read("store/index.json"))
    end
  end

  def test_a_second_sync_up_changes_nothing
    with_homes(method(:archived)) do |_first, second|
      second.run!("sync", "up")
      before = [query(second, ARCHIVES), query(second, COMPLETION), second.read("store/index.json")]
      second.run!("sync", "up")

      assert_equal before, [query(second, ARCHIVES), query(second, COMPLETION), second.read("store/index.json")]
    end
  end

  def test_unarchive_on_the_second_home_refuses_and_leaves_the_archive_mark
    with_homes(method(:archived)) do |_first, second|
      second.run!("sync", "up")
      call = second.run("intent", "unarchive", "1")

      assert_equal 1, call.code
      assert_match(/snapshot is on the first home/, call.reason)
      assert_equal [[nil]], query(second, "SELECT restored_at FROM archives")
      refute File.exist?(second.path(DIR))
    end
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

  def test_a_parked_and_an_abandoned_intent_keep_their_reason_and_disposition_on_a_second_home
    with_homes(method(:kept)) do |first, second|
      second.run!("sync", "up")
      sql = "SELECT intent_id, status, disposition, reason FROM intents ORDER BY intent_id"

      assert_includes query(second, sql), ["2", "parked", nil, "Waiting for the supplier"]
      assert_equal query(first, sql), query(second, sql)
    end
  end
end
