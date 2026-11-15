# frozen_string_literal: true

require_relative "../../../../test_helper"

# Step 27: the links between intents are a part of store/index.json, printed by every link command and read by sync up.
class KnowledgeSyncTwoHomesLinksTest < Plastic::TestCase
  include TwoHomesLinksHelper

  def test_a_link_command_prints_an_index_that_lists_the_link_and_records_the_part_row
    to_both_homes do |a, _b|
      link(a, "2", "cites", "1")

      assert_equal [[CITES], true], [listed_keys(a), printed_part?(a)]
    end
  end

  def test_a_copy_on_a_home_with_no_rows_reads_the_links_of_the_files
    to_both_homes do |a, _b|
      link(a, "2", "cites", "1")
      with_home do |c|
        pull(c, a)
        up = call_in(c, "sync", "up")

        assert_equal [0, [CITES]], [up.code, links(c)], said(up)
      end
    end
  end

  def test_a_home_whose_databases_were_removed_reads_its_links_back_from_its_files
    with_home do |home|
      seed(home)
      link(home, "2", "source", "1")
      Plastic::Graph::Database::ConnectionPool.release(File.dirname(home))
      Dir.glob(File.join(store_of(home), "*.db*")).each { |file| File.delete(file) }
      up = call_in(home, "sync", "up")

      assert_equal [0, [%w[2 1 source]]], [up.code, links(home)], said(up)
    end
  end

  def test_a_link_made_on_the_first_home_reaches_the_second_home_and_a_second_sync_up_writes_nothing
    to_both_homes do |a, b|
      link(a, "2", "cites", "1")
      pull(b, a)
      up = call_in(b, "sync", "up")
      before = files_snapshot(b)
      again = call_in(b, "sync", "up")

      assert_equal [0, [CITES], 0, before], [up.code, links(b), again.code, files_snapshot(b)], said(up) + said(again)
    end
  end

  def test_a_link_removed_on_the_first_home_is_gone_on_the_second_home_after_sync_up
    to_both_homes do |a, b|
      link(a, "2", "cites", "1")
      pull(b, a)
      call_in(b, "sync", "up")
      held = links(b)
      unlink(a, "2", "cites", "1")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [[CITES], 0, []], [held, up.code, links(b)], said(up)
    end
  end

  def test_an_intent_that_a_live_intent_links_to_on_the_first_home_stays_unarchived_on_the_second_home
    to_both_homes do |a, b|
      link(a, "2", "cites", "1")
      close_intent(a, "1")
      pull(b, a)
      call_in(b, "sync", "up")
      archive = call_in(b, "intent", "archive", "--older-than", "2099-01-01")

      assert_equal [0, []], [archive.code, home_graphs(b).retrieval.archive_rows.map(&:intent_id)], said(archive)
    end
  end

  private

  def close_intent(home, intent_id)
    row = home_graphs(home).retrieval.intent(intent_id).new_row.merge(TwoHomesStatusHelper::CLOSED)
    database_of(home, :work).transaction { |batch| batch.put(:intents, row) }
    call_in(home, "sync", "down")
  end
end
