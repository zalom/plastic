require "minitest/autorun"
require "tmpdir"
require "json"
require "fileutils"
require "open3"

require_relative "../scripts/lib/boot_banner"

# Unit coverage for the pure boot-banner renderer (intent 36a). Health is
# injected, so these are fully hermetic — no doctor run, no ~/.claude, no ENV.
class BootBannerTest < Minitest::Test
  def test_pass_renders_loaded_with_version
    health = { status: "pass", checks: [{ name: "hooks_exist", status: "pass", message: "ok" }] }
    assert_equal "Plastic Core loaded — v1.2.3", BootBanner.render(health: health, version: "1.2.3")
  end

  def test_pass_without_version_says_unknown
    health = { status: "pass", checks: [] }
    assert_equal "Plastic Core loaded — vunknown", BootBanner.render(health: health, version: nil)
  end

  def test_fail_names_first_failing_check
    health = { status: "fail", checks: [
      { name: "hooks_exist", status: "pass", message: "ok" },
      { name: "scripts_present", status: "fail", message: "missing folgezettel-id" },
    ] }
    out = BootBanner.render(health: health, version: "1.2.3")
    assert_includes out, "Plastic Core loaded with issues"
    assert_includes out, "scripts_present: missing folgezettel-id"
    assert_includes out, "run /plastic-doctor"
  end

  def test_warn_used_when_no_fail_present
    health = { status: "warn", checks: [{ name: "version_match", status: "warn", message: "mismatch" }] }
    out = BootBanner.render(health: health, version: "1.2.3")
    assert_includes out, "version_match: mismatch"
  end

  def test_non_pass_with_no_problem_check_uses_generic_issue_line
    health = { status: "fail", checks: [] }
    out = BootBanner.render(health: health, version: "1.2.3")
    assert_includes out, "Plastic Core loaded with issues"
    assert_includes out, "run /plastic-doctor"
  end

  def test_nil_health_is_error_banner
    out = BootBanner.render(health: nil, version: "1.2.3")
    assert_includes out, "Plastic Core: health check error"
    assert_includes out, "run /plastic-doctor"
  end
end

# End-to-end smoke test: invoke hook-session-start as a real subprocess against a
# tmp store. The tmp store lacks core files (PLASTIC.md, VERSION, scripts), so the
# in-process core check reports issues — exercising the degraded, non-blocking
# path deterministically regardless of the host's ~/.claude state.
class SessionStartHookTest < Minitest::Test
  HOOK = File.expand_path("../scripts/hook-session-start", __dir__)

  def setup
    @dir = Dir.mktmpdir("plastic-session-start-test")
    @index = File.join(@dir, "INDEX.md")
    File.write(@index, "# Index\n\n## Active\n\n## Future\n")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def run_hook
    Open3.capture3("ruby", HOOK, @index, @dir, "global")
  end

  def context_from(stdout)
    JSON.parse(stdout).dig("hookSpecificOutput", "additionalContext")
  end

  def test_emits_boot_banner_and_exits_zero
    out, _err, status = run_hook
    assert_equal 0, status.exitstatus
    refute_empty out.strip
    assert_includes context_from(out), "Plastic Core loaded"
  end

  def test_broken_core_warns_but_does_not_block
    out, _err, status = run_hook
    assert_equal 0, status.exitstatus, "session start must never block"
    ctx = context_from(out)
    assert_includes ctx, "with issues"
    assert_includes ctx, "run /plastic-doctor"
  end
end
