# frozen_string_literal: true

require_relative "../../../../test_helper"

# Step 24, the roadmap kind: a file changed and rows changed without a print are a conflict, and the three ways to settle it.
class KnowledgeSyncTwoHomesRoadmapConflictTest < Plastic::TestCase
  include TwoHomesRoadmapHelper

  # B's rows changed with no print, and A's changed file arrived.
  def conflicting
    to_both_homes do |a, b|
      call_in(a, "roadmap", "log", "r1", "note from A")
      put_log(b, position: 50, text: "row of B")
      pull(b, a)
      yield b
    end
  end

  def test_a_roadmap_file_changed_and_rows_changed_without_a_print_are_a_conflict_that_writes_nothing
    conflicting do |b|
      rows = logs(b)
      files = files_snapshot(b)
      up = call_in(b, "sync", "up")

      assert_equal [3, true, rows, files], [up.code, said(up).include?(FILE), logs(b), files_snapshot(b)], said(up)
    end
  end

  def test_overwrite_of_the_path_on_sync_up_reads_the_file_and_settles_the_conflict
    conflicting do |b|
      up = call_in(b, "sync", "up", "--overwrite", FILE)

      assert_equal [0, true, false], [up.code, logs(b).include?("note from A"), logs(b).include?("row of B")], said(up)
    end
  end

  def test_overwrite_of_the_path_on_sync_down_prints_the_rows_over_the_file
    conflicting do |b|
      down = call_in(b, "sync", "down", "--overwrite", FILE)

      assert_equal [0, true, false], [down.code, read_file(b, FILE).include?("row of B"), read_file(b, FILE).include?("note from A")], said(down)
    end
  end

  def test_merge_lists_the_conflict_of_a_roadmap_and_exits_as_a_refusal
    conflicting do |b|
      up = call_in(b, "sync", "up", "--merge")

      assert_equal [3, true], [up.code, said(up).include?(FILE)], said(up)
    end
  end
end
