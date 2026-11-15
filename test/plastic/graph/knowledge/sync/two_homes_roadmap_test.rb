# frozen_string_literal: true

require_relative "../../../../test_helper"

# Step 24, the roadmap kind: a roadmap file that differs from its last print on a home that holds its rows is read into rows.
class KnowledgeSyncTwoHomesRoadmapTest < Plastic::TestCase
  include TwoHomesRoadmapHelper

  def test_a_change_on_the_first_home_reaches_the_rows_of_the_second_home
    to_both_homes do |a, b|
      call_in(a, "roadmap", "log", "r1", "note from A")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, true, true], [up.code, logs(b).include?("note from A"), read_file(b, FILE).include?("note from A")], said(up)
    end
  end

  def test_a_second_sync_up_after_a_roadmap_read_writes_nothing
    to_both_homes do |a, b|
      call_in(a, "roadmap", "log", "r1", "note from A")
      pull(b, a)
      call_in(b, "sync", "up")
      before = [files_snapshot(b), logs(b)]
      again = call_in(b, "sync", "up")

      assert_equal [0, before], [again.code, [files_snapshot(b), logs(b)]], said(again)
    end
  end

  def test_a_hand_edit_of_a_roadmap_file_on_a_home_that_works_alone_is_read_into_rows
    with_home do |home|
      seed(home)
      write_file(home, FILE, read_file(home, FILE).sub(/^goal: A goal$/, "goal: by hand"))
      up = call_in(home, "sync", "up")

      assert_equal [0, "by hand"], [up.code, goal(home)], said(up)
    end
  end

  def test_the_same_change_on_both_homes_is_recorded_and_is_no_conflict
    to_both_homes do |a, b|
      call_in(a, "roadmap", "log", "r1", "same note")
      put_log(b, rows_of(a, :work, "SELECT position, at, text, session_id FROM roadmap_log WHERE text = 'same note'").first.transform_keys(&:to_sym))
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, 1], [up.code, logs(b).count("same note")], said(up)
    end
  end

  def test_a_roadmap_file_that_cannot_be_read_is_left_as_written_listed_and_the_rows_stay
    to_both_homes do |_a, b|
      write_file(b, FILE, "not a roadmap\n")
      rows = logs(b)
      up = call_in(b, "sync", "up")

      assert_equal [1, "not a roadmap\n", rows, true], [up.code, read_file(b, FILE), logs(b), said(up).include?("sync down --overwrite #{FILE}")], said(up)
    end
  end

  def test_a_roadmap_file_deleted_on_the_first_home_is_printed_again_on_the_second_home_by_sync_down
    to_both_homes do |a, b|
      File.delete(File.join(store_of(a), FILE))
      pull(b, a)
      down = call_in(b, "sync", "down")

      assert_equal [0, true], [down.code, File.exist?(File.join(store_of(b), FILE))], said(down)
    end
  end

  def test_a_home_that_holds_no_rows_for_the_roadmap_reads_the_file_as_the_older_step_does
    two_homes do |a, b|
      seed(a)
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, ["Road"]], [up.code, rows_of(b, :work, "SELECT title FROM roadmaps WHERE slug = 'r1'").map { |row| row["title"] }], said(up)
    end
  end

  def test_a_roadmap_read_leaves_the_rows_of_another_origin_and_duplicates_no_row
    to_both_homes do |a, b|
      put_log(b, position: 90, text: "foreign", origin_id: "other-origin")
      call_in(a, "roadmap", "log", "r1", "note from A")
      pull(b, a)
      2.times { call_in(b, "sync", "up") }

      assert_equal [1, 1], [logs(b).count("note from A"), logs(b).count("foreign")]
    end
  end

  def test_a_roadmap_file_that_only_the_first_home_printed_gets_an_entry
    two_homes do |a, b|
      seed(a)
      pull(b, a)

      assert_includes Plastic::Graph::Knowledge::Sync::EntryList.new(folder_of(b), home_graphs(b).retrieval).on_disk, FILE
    end
  end
end
