# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../scripts/lib/store_sync"

class StoreSyncTest < Minitest::Test
  def action(file, row, recorded)
    Plastic::StoreSync.action("file" => file, "row" => row, "hash" => recorded)
  end

  def test_nothing_changed_is_no_action
    assert_nil action("a", "a", "a")
  end

  def test_a_changed_file_is_read_into_the_row
    assert_equal "read", action("b", "a", "a")
  end

  def test_a_changed_row_is_written_out
    assert_equal "write", action("a", "b", "a")
  end

  def test_both_changed_is_a_conflict
    assert_equal "conflict", action("b", "c", "a")
  end

  def test_both_changed_to_the_same_text_is_no_action
    assert_nil action("b", "b", "a")
  end

  def test_a_missing_file_is_written_out
    assert_equal "write", action(nil, "a", "a")
  end
end
