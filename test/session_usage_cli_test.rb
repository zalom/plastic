# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"

# Intent 355, n1: scripts/session-usage runs as a subprocess, prints text by
# default and JSON with --format json, and exits 0.
class SessionUsageCliTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/session-usage", __dir__)
  FIXTURE_ROOT = File.expand_path("fixtures/transcripts", __dir__)

  def setup
    @home = Dir.mktmpdir("session-usage-cli")
    @root = File.join(@home, "projects")
    FileUtils.mkdir_p(@root)
    FileUtils.cp_r(File.join(FIXTURE_ROOT, "."), @root)
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def run_cli(*args, root: @root)
    Open3.capture3(RbConfig.ruby, SCRIPT, "--root", root,
                   "--rate-limits", File.join(@home, "rate-limits.json"),
                   "--since", "2026-09-12T00:00:00Z", *args)
  end

  def test_subprocess_text_and_json
    out, err, status = run_cli
    assert_equal 0, status.exitstatus, err
    assert_match(/calls/, out)
    assert_match(/agent-afixture00000001/, out)
    assert_match(/claude-opus-5/, out)

    out, err, status = run_cli("--format", "json")
    assert_equal 0, status.exitstatus, err
    report = JSON.parse(out)
    assert_equal "ok", report["status"]
    assert_equal "since", report["cutoff_source"]
    assert_equal [2], report["sessions"].map { |s| s["calls"] }

    out, err, status = run_cli(root: File.join(@home, "missing"))
    assert_equal 0, status.exitstatus, err
    assert_match(/unavailable/, out)

    _out, _err, status = run_cli("--format", "xml")
    assert_equal 2, status.exitstatus
  end
end
