# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/workflows/run_times"

class RunTimesTest < Minitest::Test
  def run_times = Plastic::Workflows::RunTimes

  def test_the_length_reads_plainly_at_each_edge
    cases = { 0 => "under 1s", 1 => "1s", 59 => "59s", 60 => "1m 0s", 252 => "4m 12s", 3599 => "59m 59s", 3600 => "1h 0m 0s", 3723 => "1h 2m 3s" }

    cases.each { |seconds, text| assert_equal text, run_times.length(seconds), "#{seconds} seconds" }
  end

  def test_the_length_of_a_run_that_ends_before_it_starts_is_under_one_second
    assert_equal "under 1s", run_times.length(-3)
  end

  def test_the_seconds_come_from_the_stored_times
    assert_equal 252, run_times.seconds("2026-11-23T10:00:00Z", "2026-11-23T10:04:12+00:00")
  end

  def test_the_times_show_in_the_zone_they_are_given_with_its_offset
    assert_equal "started 2026-11-23T19:00:00+09:00, ended 2026-11-23T19:04:12+09:00, length 4m 12s",
      run_times.span("2026-11-23T10:00:00Z", "2026-11-23T10:04:12Z", "+09:00")
  end

  def test_a_run_with_no_end_shows_its_start_in_the_zone_it_is_given_and_says_running
    assert_equal "started 2026-11-23T19:00:00+09:00, running", run_times.span("2026-11-23T10:00:00Z", nil, "+09:00")
  end

  def test_the_length_does_not_change_with_the_zone
    assert_equal "4m 12s", run_times.span("2026-11-23T10:00:00Z", "2026-11-23T10:04:12Z", "-05:00").split("length ").last
  end
end
