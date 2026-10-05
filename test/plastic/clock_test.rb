# frozen_string_literal: true

require_relative "../test_helper"

class ClockTest < Plastic::TestCase
  def test_now_writes_the_local_time_with_its_offset
    assert_equal "2026-10-05T10:00:00+02:00", Plastic.now(Time.new(2026, 10, 5, 10, 0, 0, "+02:00"))
  end
end
