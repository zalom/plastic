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
end
