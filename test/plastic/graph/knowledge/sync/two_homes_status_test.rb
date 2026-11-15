# frozen_string_literal: true

require_relative "../../../../test_helper"

# Step 26: the title and the state of an intent in an index that another home printed, on a home that holds a print of the index.
class KnowledgeSyncTwoHomesStatusTest < Plastic::TestCase
  include TwoHomesStatusHelper

  def test_a_retitle_on_the_first_home_reaches_the_row_of_the_second_home
    to_both_homes do |a, b|
      change_row(a, "1", title: "Retitled by A")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, "Retitled by A"], [up.code, fields(b, "1")["title"]], said(up)
    end
  end

  def test_a_close_with_a_reason_on_the_first_home_reaches_the_row_of_the_second_home
    to_both_homes do |a, b|
      change_row(a, "1", **CLOSED)
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, fields(a, "1")], [up.code, fields(b, "1")], said(up)
    end
  end

  def test_a_field_that_does_not_cross_keeps_the_value_of_the_second_home
    to_both_homes do |a, b|
      change_row(b, "1", ref: "ticket-7")
      change_row(a, "1", title: "Retitled by A", ref: "ticket-9")
      pull(b, a)
      call_in(b, "sync", "up")

      assert_equal ["ticket-7", "Retitled by A"], [intent_row(b, "1")["ref"], intent_row(b, "1")["title"]]
    end
  end

  def test_an_entry_whose_intent_has_no_folder_on_the_second_home_gives_no_row
    to_both_homes do |a, b|
      call_in(a, "intent", "new", "Gamma")
      write_file(b, FILE, read_file(a, FILE))
      up = call_in(b, "sync", "up")

      assert_equal [0, nil], [up.code, intent_row(b, "3")], said(up)
    end
  end

  def test_an_entry_of_a_third_origin_is_refused_listed_and_leaves_the_rows
    to_both_homes do |a, b|
      change_row(a, "1", title: "Retitled by A")
      pull(b, a)
      list_first_intent_of_a_third_origin(b)
      up = call_in(b, "sync", "up")

      assert_equal [1, "Alpha", true], [up.code, fields(b, "1")["title"], said(up).include?("sync down --overwrite #{FILE}")], said(up)
    end
  end

  def test_a_copy_on_a_home_with_no_print_of_the_index_takes_the_titles_of_the_folders
    to_both_homes do |a, _b|
      change_row(a, "1", title: "Retitled by A")
      with_home do |c|
        pull(c, a)
        up = call_in(c, "sync", "up")

        assert_equal [0, "Retitled by A"], [up.code, fields(c, "1")["title"]], said(up)
      end
    end
  end

  def test_after_the_read_the_index_carries_the_origin_of_the_second_home_and_a_second_sync_up_writes_nothing
    to_both_homes do |a, b|
      change_row(a, "1", **CLOSED)
      pull(b, a)
      call_in(b, "sync", "up")
      before = files_snapshot(b)
      again = call_in(b, "sync", "up")

      assert_equal [0, origin_of(b), before], [again.code, index_of(b)["origin_id"], files_snapshot(b)], said(again)
    end
  end

  def test_a_hand_edit_of_a_title_in_the_own_index_of_a_home_that_works_alone_is_read
    with_home do |home|
      seed(home)
      call_in(home, "sync", "down")
      data = index_of(home)
      data["intents"].first["title"] = "By hand"
      write_file(home, FILE, JSON.pretty_generate(data))
      up = call_in(home, "sync", "up")

      assert_equal [0, "By hand"], [up.code, fields(home, "1")["title"]], said(up)
    end
  end
end
