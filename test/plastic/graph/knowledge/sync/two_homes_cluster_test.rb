# frozen_string_literal: true

require_relative "../../../../test_helper"

# Step 24, the cluster kind: the clusters of an index that differ from their last print on a home that holds their rows are read into rows.
class KnowledgeSyncTwoHomesClusterTest < Plastic::TestCase
  include TwoHomesClusterHelper

  def test_a_change_on_the_first_home_reaches_the_rows_of_the_second_home
    to_both_homes do |a, b|
      change_clusters(a, "two", "2")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, [%w[one 1], %w[two 2]], %w[one two]], [up.code, clusters(b), listed(b)], said(up)
    end
  end

  def test_a_second_sync_up_after_a_cluster_read_writes_nothing
    to_both_homes do |a, b|
      change_clusters(a, "two", "2")
      pull(b, a)
      call_in(b, "sync", "up")
      before = [files_snapshot(b), clusters(b)]
      again = call_in(b, "sync", "up")

      assert_equal [0, before], [again.code, [files_snapshot(b), clusters(b)]], said(again)
    end
  end

  def test_a_hand_edit_of_the_clusters_on_a_home_that_works_alone_is_read_into_rows
    with_home do |home|
      seed(home)
      call_in(home, "sync", "down")
      data = JSON.parse(read_file(home, FILE))
      write_file(home, FILE, JSON.pretty_generate(data.merge("clusters" => [{ "name" => "by hand", "intents" => %w[1 2] }])))
      up = call_in(home, "sync", "up")

      assert_equal [0, [["by hand", "1"], ["by hand", "2"]]], [up.code, clusters(home)], said(up)
    end
  end

  def test_the_same_change_on_both_homes_is_recorded_and_is_no_conflict
    to_both_homes do |a, b|
      change_clusters(a, "same", "1")
      put_cluster(b, "same", "1")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, [%w[one 1], %w[same 1]]], [up.code, clusters(b)], said(up)
    end
  end

  def test_clusters_that_cannot_be_read_are_left_as_written_listed_and_the_rows_stay
    to_both_homes do |_a, b|
      data = JSON.parse(read_file(b, FILE))
      write_file(b, FILE, JSON.pretty_generate(data.merge("clusters" => [{ "name" => "bad", "intents" => "1" }])))
      written = read_file(b, FILE)
      up = call_in(b, "sync", "up")

      assert_equal [1, written, [%w[one 1]], true], [up.code, read_file(b, FILE), clusters(b), said(up).include?("sync down --overwrite #{FILE}")], said(up)
    end
  end

  def test_an_index_deleted_on_the_first_home_is_printed_again_on_the_second_home_by_sync_down
    to_both_homes do |a, b|
      File.delete(File.join(store_of(a), FILE))
      pull(b, a)
      down = call_in(b, "sync", "down")

      assert_equal [0, true, [%w[one 1]]], [down.code, File.exist?(File.join(store_of(b), FILE)), clusters(b)], said(down)
    end
  end

  def test_a_home_that_holds_no_rows_for_the_clusters_reads_the_file_as_the_older_step_does
    two_homes do |a, b|
      seed(a)
      call_in(a, "sync", "down")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, [%w[one 1]]], [up.code, clusters(b)], said(up)
    end
  end

  def test_a_cluster_read_leaves_the_rows_of_another_origin_and_duplicates_no_row
    to_both_homes do |a, b|
      put_cluster(b, "foreign", "1", origin: "zzz-other")
      call_in(b, "sync", "down")
      change_clusters(a, "two", "2")
      pull(b, a)
      2.times { call_in(b, "sync", "up") }

      assert_equal [[%w[one 1], %w[two 2]], [%w[foreign 1]]], [clusters(b), clusters(b, origin: "zzz-other")]
    end
  end

  def test_the_part_of_the_clusters_gets_no_file_and_sync_down_writes_none_with_a_hash_in_its_name
    to_both_homes do |a, _b|
      change_clusters(a, "two", "2")

      assert_equal [], files_of(a).select { |rel| rel.include?("#") }
    end
  end
end
