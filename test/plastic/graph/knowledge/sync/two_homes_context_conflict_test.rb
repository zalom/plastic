# frozen_string_literal: true

require_relative "../../../../test_helper"

# Step 24, the context kind: a file changed and rows changed without a print are a conflict, and the three ways to settle it.
class KnowledgeSyncTwoHomesContextConflictTest < Plastic::TestCase
  include TwoHomesContextHelper

  # B's rows changed with no print, and A's changed file arrived.
  def conflicting
    to_both_homes do |a, b|
      change_part(a, "context", { "note" => "from A" })
      put_part(b, "context", { "note" => "row of B" })
      pull(b, a)
      yield b
    end
  end

  def test_a_context_file_changed_and_rows_changed_without_a_print_are_a_conflict_that_writes_nothing
    conflicting do |b|
      rows = part_of(b, "context")
      files = files_snapshot(b)
      up = call_in(b, "sync", "up")

      assert_equal [3, true, rows, files], [up.code, said(up).include?(FILE), part_of(b, "context"), files_snapshot(b)], said(up)
    end
  end

  def test_overwrite_of_the_path_on_sync_up_reads_the_file_and_settles_the_conflict
    conflicting do |b|
      up = call_in(b, "sync", "up", "--overwrite", FILE)

      assert_equal [0, { "note" => "from A" }], [up.code, part_of(b, "context")], said(up)
    end
  end

  def test_overwrite_of_the_path_on_sync_down_prints_the_rows_over_the_file
    conflicting do |b|
      down = call_in(b, "sync", "down", "--overwrite", FILE)

      assert_equal [0, "row of B"], [down.code, file_part(b, "context")["note"]], said(down)
    end
  end

  def test_merge_lists_the_conflict_of_a_context_and_exits_as_a_refusal
    conflicting do |b|
      up = call_in(b, "sync", "up", "--merge")

      assert_equal [3, true], [up.code, said(up).include?(FILE)], said(up)
    end
  end
end
