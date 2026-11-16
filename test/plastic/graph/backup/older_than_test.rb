# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/backup/older_than"

class GraphBackupOlderThanTest < Plastic::TestCase
  OlderThan = Plastic::Graph::Backup::OlderThan

  def test_a_date_is_local_midnight_of_that_day
    assert_equal Time.new(2026, 10, 5), OlderThan.parse("2026-10-05")
  end

  def test_a_full_time_with_an_offset_is_read_as_given
    assert_equal Time.utc(2026, 10, 5, 14, 0, 0), OlderThan.parse("2026-10-05T16:00:00+02:00")
  end

  def test_a_full_time_may_use_a_space_in_place_of_the_t
    assert_equal Time.utc(2026, 10, 5, 16, 0, 0), OlderThan.parse("2026-10-05 16:00:00Z")
  end

  def test_text_that_is_neither_a_date_nor_a_full_time_is_unreadable
    error = assert_raises(OlderThan::Unreadable) { OlderThan.parse("last week") }

    assert_includes error.message, "last week"
  end

  def test_a_date_that_does_not_exist_is_unreadable
    assert_raises(OlderThan::Unreadable) { OlderThan.parse("2026-13-45") }
  end

  def test_a_day_that_the_month_does_not_have_is_unreadable_instead_of_rolling_over
    error = assert_raises(OlderThan::Unreadable) { OlderThan.parse("2026-02-30") }

    assert_includes error.message, "2026-02-30"
  end

  def test_the_last_day_of_a_leap_february_is_a_day
    assert_equal Time.new(2028, 2, 29), OlderThan.parse("2028-02-29")
  end

  def test_a_time_with_no_offset_is_unreadable
    assert_raises(OlderThan::Unreadable) { OlderThan.parse("2026-10-05 16:00:00") }
  end
end
