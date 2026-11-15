# frozen_string_literal: true

require_relative "../../../../test_helper"

# Step 24, the context kind: a context.json that differs from its last print on a home that holds its rows is read into rows.
class KnowledgeSyncTwoHomesContextTest < Plastic::TestCase
  include TwoHomesContextHelper

  def test_a_change_on_the_first_home_reaches_the_rows_of_the_second_home
    to_both_homes do |a, b|
      change_part(a, "context", { "note" => "from A" })
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, { "note" => "from A" }, "from A"], [up.code, part_of(b, "context"), file_part(b, "context")["note"]], said(up)
    end
  end

  def test_a_second_sync_up_after_a_context_read_writes_nothing
    to_both_homes do |a, b|
      change_part(a, "context", { "note" => "from A" })
      pull(b, a)
      call_in(b, "sync", "up")
      before = [files_snapshot(b), part_of(b, "context")]
      again = call_in(b, "sync", "up")

      assert_equal [0, before], [again.code, [files_snapshot(b), part_of(b, "context")]], said(again)
    end
  end

  def test_a_hand_edit_of_a_context_file_on_a_home_that_works_alone_is_read_into_rows
    with_home do |home|
      seed(home)
      call_in(home, "sync", "down")
      write_file(home, FILE, JSON.generate(JSON.parse(read_file(home, FILE)).merge("context" => { "note" => "by hand" })))
      up = call_in(home, "sync", "up")

      assert_equal [0, { "note" => "by hand" }], [up.code, part_of(home, "context")], said(up)
    end
  end

  def test_the_same_change_on_both_homes_is_recorded_and_is_no_conflict
    to_both_homes do |a, b|
      change_part(a, "context", { "note" => "same" })
      put_part(b, "context", { "note" => "same" })
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, { "note" => "same" }], [up.code, part_of(b, "context")], said(up)
    end
  end

  def test_a_context_file_that_cannot_be_read_is_left_as_written_listed_and_the_rows_stay
    to_both_homes do |_a, b|
      write_file(b, FILE, "not json\n")
      rows = part_of(b, "context")
      up = call_in(b, "sync", "up")

      assert_equal [1, "not json\n", rows, true], [up.code, read_file(b, FILE), part_of(b, "context"), said(up).include?("sync down --overwrite #{FILE}")], said(up)
    end
  end

  def test_a_context_file_deleted_on_the_first_home_is_printed_again_on_the_second_home_by_sync_down
    to_both_homes do |a, b|
      File.delete(File.join(store_of(a), FILE))
      pull(b, a)
      down = call_in(b, "sync", "down")

      assert_equal [0, true], [down.code, File.exist?(File.join(store_of(b), FILE))], said(down)
    end
  end

  def test_a_home_that_holds_no_rows_for_the_context_reads_the_file_as_the_older_step_does
    two_homes do |a, b|
      seed(a)
      call_in(a, "sync", "down")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, { "note" => "first" }], [up.code, part_of(b, "context")], said(up)
    end
  end

  def test_a_context_read_leaves_the_rows_of_another_origin_and_duplicates_no_row
    to_both_homes do |a, b|
      put_part(b, "context", { "note" => "foreign" }, origin: "zzz-other")
      change_part(a, "context", { "note" => "from A" })
      pull(b, a)
      2.times { call_in(b, "sync", "up") }

      assert_equal [{ "note" => "from A" }, { "note" => "foreign" }], [part_of(b, "context"), part_of(b, "context", origin: "zzz-other")]
    end
  end

  def test_a_context_file_that_only_the_first_home_printed_gets_an_entry
    two_homes do |a, b|
      seed(a)
      call_in(a, "sync", "down")
      pull(b, a)

      assert_includes Plastic::Graph::Knowledge::Sync::EntryList.new(folder_of(b), home_graphs(b).retrieval).on_disk, FILE
    end
  end
end
