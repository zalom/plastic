# frozen_string_literal: true

require_relative "../test_helper"

class ClockTest < Plastic::TestCase
  TOKYO = "+09:00"
  NEW_YORK = "-04:00"

  def test_a_timestamp_writes_the_time_in_utc
    assert_equal "2026-10-05T08:00:00Z", Plastic.timestamp(Time.new(2026, 10, 5, 10, 0, 0, "+02:00"))
  end

  def test_a_timestamp_reads_the_same_whatever_offset_the_clock_gives
    stamps = [NEW_YORK, TOKYO].map { |zone| Plastic.timestamp(Time.utc(2026, 10, 5, 8, 0, 0).getlocal(zone)) }

    assert_equal ["2026-10-05T08:00:00Z"] * 2, stamps
  end

  def test_a_utc_time_shows_in_the_zone_it_is_given_with_its_offset
    assert_equal "2026-10-05T17:00:00+09:00", Plastic.local("2026-10-05T08:00:00Z", TOKYO)
  end

  def test_a_time_with_an_offset_shows_in_the_zone_it_is_given
    assert_equal "2026-10-05T04:00:00-04:00", Plastic.local("2026-10-05T10:00:00+02:00", NEW_YORK)
  end

  def test_a_time_shows_in_the_zone_of_the_machine_when_no_zone_is_given
    assert_equal Time.utc(2026, 10, 5, 8, 0, 0).getlocal.iso8601, Plastic.local("2026-10-05T08:00:00Z")
  end

  def test_a_date_a_blank_and_an_unreadable_value_show_as_they_are
    values = ["2026-10-05", "", nil, "then", "2026-13-45T99:00:00Z"]

    assert_equal values, values.map { |value| Plastic.local(value, TOKYO) }
  end

  def test_a_utc_time_falls_on_the_calendar_day_of_the_zone_it_is_given
    assert_equal "2026-10-06", Plastic.local_day("2026-10-05T20:00:00Z", TOKYO)
  end

  def test_a_date_a_blank_and_other_text_have_no_day
    values = ["2026-10-05", "", nil, "then"]

    assert_equal [nil] * 4, values.map { |value| Plastic.local_day(value, TOKYO) }
  end

  def test_an_impossible_time_has_no_day_and_raises
    assert_raises(ArgumentError) { Plastic.local_day("2026-13-45T99:00:00Z", TOKYO) }
  end

  def test_a_time_read_with_an_offset_becomes_its_time_in_utc
    assert_equal "2026-10-05T08:00:00Z", Plastic.utc("2026-10-05T10:00:00+02:00")
  end

  def test_a_date_a_blank_a_utc_time_and_other_text_read_as_they_are
    values = ["2026-10-05", "", nil, "then", "2026-10-05T08:00:00Z"]

    assert_equal values, values.map { |value| Plastic.utc(value) }
  end

  def test_the_time_fields_of_a_row_read_in_utc_and_its_other_fields_as_they_are
    fields = { at: "2026-10-05T10:00:00+02:00", seen_at: "2026-10-05T10:00:00+02:00", title: "2026-10-05T10:00:00+02:00", batch: 1 }

    assert_equal({ at: "2026-10-05T08:00:00Z", seen_at: "2026-10-05T08:00:00Z", title: "2026-10-05T10:00:00+02:00", batch: 1 }, Plastic.utc_fields(fields))
  end

  def test_an_impossible_time_read_from_a_file_raises_and_names_the_text
    error = assert_raises(Plastic::Invalid) { Plastic.utc("2026-11-21T25:00:00+02:00") }

    assert_includes error.message, "2026-11-21T25:00:00+02:00"
  end
end
