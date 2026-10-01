# frozen_string_literal: true

require_relative "../test_helper"

class PlasticTest < Plastic::TestCase
  def test_now_is_local_time_with_its_offset
    now = Plastic.now

    assert_match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d\z/, now)
    assert_equal Time.now.utc_offset, Time.iso8601(now).utc_offset
  end
end
