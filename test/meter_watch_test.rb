# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "time"
require_relative "../scripts/lib/meter_watch"

# Intent 355, n5: MeterWatch reads the rate-limit cache on a timer and writes
# one state file a session can watch, instead of every session parsing the
# cache and the thresholds itself. Everything is injected (home, clock, cache
# path, renamer); nothing reads ENV and nothing touches a real LaunchAgent.
class MeterWatchTest < Minitest::Test
  NOW = Time.utc(2026, 9, 12, 10, 0, 0)

  def setup
    @home = Dir.mktmpdir("meter-watch")
    @cache_path = File.join(@home, ".cache", "rate-limits.json")
    @state_path = File.join(@home, ".cache", "meter-state.json")
    FileUtils.mkdir_p(File.dirname(@cache_path))
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def write_cache(five_hour: 10, seven_day: 10, resets_at: NOW + 3600, at: NOW)
    File.write(@cache_path, JSON.generate("five_hour" => five_hour, "seven_day" => seven_day,
                                           "resets_at" => resets_at.to_i.to_s))
    File.utime(at, at, @cache_path)
  end

  def watch(now: NOW, **kwargs)
    MeterWatch.new(home: @home, now: now, **kwargs)
  end

  def read_state
    JSON.parse(File.read(@state_path))
  end

  # 5.1
  def test_state_file_fields
    write_cache(five_hour: 20, seven_day: 30, resets_at: NOW + 1800)

    result = watch.tick

    %w[state five_hour seven_day resets_at checked_at].each do |field|
      assert result.key?(field), "tick result missing #{field}"
    end
    assert_equal "ok", result["state"]
    assert_equal 20, result["five_hour"]
    assert_equal 30, result["seven_day"]
    assert_equal (NOW + 1800).to_i.to_s, result["resets_at"]
    assert_equal NOW.iso8601, result["checked_at"]
    assert_equal result, read_state
  end

  # 5.2
  def test_thresholds_by_state
    write_cache(five_hour: 54, seven_day: 10)
    assert_equal "ok", watch.tick["state"]

    write_cache(five_hour: 55, seven_day: 10)
    assert_equal "reduce", watch.tick["state"]

    write_cache(five_hour: 84, seven_day: 10)
    assert_equal "reduce", watch.tick["state"]

    write_cache(five_hour: 85, seven_day: 10)
    assert_equal "stop", watch.tick["state"]

    write_cache(five_hour: 10, seven_day: 96)
    assert_equal "ok", watch.tick["state"]

    write_cache(five_hour: 10, seven_day: 97)
    assert_equal "stop", watch.tick["state"]
  end

  # 5.3
  def test_thresholds_from_config
    File.write(File.join(@home, "config.yml"), <<~YAML)
      meter:
        reduce_at: 10
        stop_at: 20
        weekly_stop_at: 30
    YAML
    write_cache(five_hour: 15, seven_day: 5)

    assert_equal "reduce", watch.tick["state"]
  end

  # 5.4
  def test_resume_after_reset_time
    reset_at = NOW + 600
    write_cache(five_hour: 90, seven_day: 10, resets_at: reset_at)
    assert_equal "stop", watch(now: NOW).tick["state"]

    write_cache(five_hour: 90, seven_day: 10, resets_at: reset_at, at: NOW + 660)
    assert_equal "resume", watch(now: NOW + 660).tick["state"]
  end

  # B4: resume must compare against the STOP's own resets_at, not the
  # cache's current one, since the cache moves resets_at on to the next
  # window before five_hour/seven_day themselves drop.
  def test_resume_when_cache_moved_to_next_window
    reset_at = NOW + 600
    write_cache(five_hour: 90, seven_day: 10, resets_at: reset_at)
    assert_equal "stop", watch(now: NOW).tick["state"]

    next_window_reset_at = NOW + (6 * 3600)
    write_cache(five_hour: 90, seven_day: 10, resets_at: next_window_reset_at, at: NOW + 660)
    assert_equal "resume", watch(now: NOW + 660).tick["state"],
                 "now is past the stop's OWN reset time, even though the cache has already " \
                 "moved resets_at on to a later window"
  end

  # B4: a stale tick while stopped must carry the stop state forward, never
  # replace it with "stale".
  def test_stale_tick_keeps_stop
    write_cache(five_hour: 90, seven_day: 10, resets_at: NOW + 3600, at: NOW)
    assert_equal "stop", watch(now: NOW).tick["state"]

    stale_now = NOW + MeterWatch::STALE_AFTER_SECONDS + 1
    assert_equal "stop", watch(now: stale_now).tick["state"],
                 "a stale tick must carry the stop state forward, never overwrite it with stale"
  end

  # 5.5
  def test_stale_cache_is_stale_not_ok
    write_cache(five_hour: 10, seven_day: 10, at: NOW - (39 * 60))
    assert_equal "ok", watch(now: NOW).tick["state"]

    write_cache(five_hour: 10, seven_day: 10, at: NOW - (41 * 60))
    assert_equal "stale", watch(now: NOW).tick["state"]
  end

  def test_missing_cache_is_unavailable
    refute File.exist?(@cache_path)
    assert_equal "unavailable", watch.tick["state"]
  end

  # 5.6
  def test_write_atomic_and_only_on_change
    calls = []
    renamer = ->(from, to) {
      calls << to
      File.rename(from, to)
    }

    write_cache(five_hour: 10, seven_day: 10)
    watch(renamer: renamer).tick
    assert_equal 1, calls.length, "first tick must write the state file"

    write_cache(five_hour: 12, seven_day: 10)
    watch(renamer: renamer).tick
    assert_equal 1, calls.length, "an unchanged state must not write again"

    write_cache(five_hour: 90, seven_day: 10)
    watch(renamer: renamer).tick
    assert_equal 2, calls.length, "a changed state must write"

    assert_equal "stop", read_state["state"]
  end
end
