# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"

# Intent 355, n5: scripts/meter-watch runs as a subprocess, ticks the meter by
# default and writes the LaunchAgent plist under an injected home with
# --install-timer. It never calls launchctl itself.
class MeterWatchCliTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/meter-watch", __dir__)

  def setup
    @home = Dir.mktmpdir("meter-watch-cli")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def run_cli(*args)
    Open3.capture3(RbConfig.ruby, SCRIPT, "--home", @home, *args)
  end

  def test_tick_writes_state_and_prints_it
    cache_dir = File.join(@home, ".cache")
    FileUtils.mkdir_p(cache_dir)
    File.write(File.join(cache_dir, "rate-limits.json"),
               JSON.generate("five_hour" => 10, "seven_day" => 10, "resets_at" => (Time.now + 3600).to_i.to_s))

    out, err, status = run_cli
    assert_equal 0, status.exitstatus, err
    report = JSON.parse(out)
    assert_equal "ok", report["state"]
    assert File.exist?(File.join(cache_dir, "meter-state.json"))
  end

  # 5.7
  def test_install_timer_writes_plist
    out, err, status = run_cli("--install-timer")
    assert_equal 0, status.exitstatus, err

    plist_path = File.join(@home, "Library", "LaunchAgents", "com.plastic.meter-watch.plist")
    assert File.exist?(plist_path), "expected #{plist_path} to be written"
    content = File.read(plist_path)
    assert_includes content, "StartInterval"
    assert_includes content, "1200"
    assert_includes content, SCRIPT
    assert_includes out, plist_path

    refute_match(/launchctl/, content, "the plist must not shell out to launchctl")
  end
end
