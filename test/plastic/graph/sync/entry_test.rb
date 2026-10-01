# frozen_string_literal: true

require_relative "../../support/kernel"

class SyncEntryTest < Minitest::Test
  Entry = Plastic::Graph::Sync::Entry
  Print = Plastic::Graph::Prints::Print

  # The action up and down for a file hash, a recorded hash and a rows hash.
  def actions(file, printed, rows)
    entry = Entry.new("p", file, printed, rows ? Print.new("p", :work, rows, nil) : Entry::NO_PRINT)
    %i[up down].map { |direction| entry.action(direction) }
  end

  def test_a_level_file_already_recorded_needs_nothing
    assert_equal %i[none none], actions("a", "a", "a")
  end

  def test_a_level_file_not_yet_recorded_is_recorded
    assert_equal %i[record record], actions("a", nil, "a")
  end

  def test_a_hand_edit_is_read_up_and_left_down
    assert_equal %i[read none], actions("b", "a", "a")
  end

  def test_a_row_change_is_printed_down_and_left_up
    assert_equal %i[none print], actions("a", "a", "b")
  end

  def test_a_missing_file_with_rows_is_printed_down
    assert_equal %i[none print], actions(nil, "a", "a")
  end

  def test_a_change_on_both_sides_is_a_conflict
    assert_equal %i[conflict conflict], actions("b", "a", "c")
  end

  def test_a_new_file_with_no_rows_is_read_up
    assert_equal %i[read none], actions("b", nil, nil)
  end
end
