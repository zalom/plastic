# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/lib/dashboard_banner"

# Hermetic unit tests for DashboardBanner (intent 125, Task 6/9). Pure function,
# no subprocess, no file I/O: feed it payload-shaped hashes directly.
class DashboardBannerTest < Minitest::Test
  def test_renders_counts_line
    payload = { "counts" => { "active" => 2, "future" => 5 } }
    line = DashboardBanner.render(payload)
    assert_includes line, "2 active"
    assert_includes line, "5 next"
    assert_includes line, "show the dashboard"
    refute_includes line, "\n"
  end

  def test_names_next_big_thing_when_present
    payload = {
      "counts" => { "active" => 0, "future" => 1 },
      "next_work" => [{ "id" => "1", "disposition" => "drive", "line" => "1 Big idea" }],
    }
    line = DashboardBanner.render(payload)
    assert_includes line, "next big thing: 1"
  end

  def test_omits_next_big_thing_when_absent
    payload = { "counts" => { "active" => 0, "future" => 0 }, "next_work" => [] }
    line = DashboardBanner.render(payload)
    refute_includes line, "next big thing"
  end

  def test_omits_next_big_thing_when_id_blank
    payload = {
      "counts" => { "active" => 0, "future" => 0 },
      "next_work" => [{ "id" => "", "disposition" => "drive", "line" => "+2 more" }],
    }
    line = DashboardBanner.render(payload)
    refute_includes line, "next big thing"
  end

  def test_nil_payload_returns_nil
    assert_nil DashboardBanner.render(nil)
  end

  def test_non_hash_payload_returns_nil
    assert_nil DashboardBanner.render("not a hash")
  end

  def test_payload_missing_counts_returns_nil
    assert_nil DashboardBanner.render({ "next_work" => [] })
  end

  def test_malformed_next_work_shape_is_ignored_not_raised
    payload = { "counts" => { "active" => 1, "future" => 1 }, "next_work" => "not an array" }
    line = DashboardBanner.render(payload)
    refute_nil line
    refute_includes line, "next big thing"
  end
end
