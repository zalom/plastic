# frozen_string_literal: true

require_relative "../test_helper"

class ClockTest < Plastic::TestCase
  def test_a_timestamp_writes_the_time_in_utc
    assert_equal "2026-10-05T08:00:00Z", Plastic.timestamp(Time.new(2026, 10, 5, 10, 0, 0, "+02:00"))
  end

  def test_a_timestamp_reads_the_same_in_every_zone_of_the_machine
    stamps = %w[America/New_York Asia/Tokyo].map { |zone| in_zone(zone) { Plastic.timestamp(Time.utc(2026, 10, 5, 8, 0, 0).getlocal) } }

    assert_equal ["2026-10-05T08:00:00Z"] * 2, stamps
  end

  def test_a_utc_time_shows_in_the_zone_of_the_machine_with_its_offset
    assert_equal "2026-10-05T17:00:00+09:00", in_zone("Asia/Tokyo") { Plastic.local("2026-10-05T08:00:00Z") }
  end

  def test_a_time_with_an_offset_shows_in_the_zone_of_the_machine
    assert_equal "2026-10-05T04:00:00-04:00", in_zone("America/New_York") { Plastic.local("2026-10-05T10:00:00+02:00") }
  end

  def test_a_date_a_blank_and_an_unreadable_value_show_as_they_are
    values = ["2026-10-05", "", nil, "then", "2026-13-45T99:00:00Z"]

    assert_equal values, in_zone("Asia/Tokyo") { values.map { |value| Plastic.local(value) } }
  end

  def test_a_utc_time_falls_on_the_calendar_day_of_the_machine
    assert_equal "2026-10-06", in_zone("Asia/Tokyo") { Plastic.local_day("2026-10-05T20:00:00Z") }
  end

  def test_a_date_a_blank_and_an_unreadable_value_have_no_day
    values = ["2026-10-05", "", nil, "then", "2026-13-45T99:00:00Z"]

    assert_equal [nil] * 5, in_zone("Asia/Tokyo") { values.map { |value| Plastic.local_day(value) } }
  end
end
