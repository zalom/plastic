require "minitest/autorun"
require "tmpdir"
require "json"
require "fileutils"
require "open3"

require_relative "../scripts/lib/boot_banner"
require_relative "../scripts/lib/qmd_sync"

# Unit coverage for the pure boot-banner renderer (intent 36a). Health is
# injected, so these are fully hermetic — no doctor run, no ~/.claude, no ENV.
class BootBannerTest < Minitest::Test
  def test_pass_renders_loaded_with_version
    health = { status: "pass", checks: [{ name: "hooks_exist", status: "pass", message: "ok" }] }
    assert_equal "Plastic Core loaded — v1.2.3 | doctor --core run: success",
                 BootBanner.render(health: health, version: "1.2.3")
  end

  def test_pass_without_version_says_unknown
    health = { status: "pass", checks: [] }
    assert_equal "Plastic Core loaded — vunknown | doctor --core run: success",
                 BootBanner.render(health: health, version: nil)
  end

  def test_fail_yields_binary_error_line
    health = { status: "fail", checks: [
      { name: "hooks_exist", status: "pass", message: "ok" },
      { name: "scripts_present", status: "fail", message: "missing folgezettel-id" },
    ] }
    out = BootBanner.render(health: health, version: "1.2.3")
    assert_equal "Plastic Core loaded — v1.2.3 | doctor --core run: error — run /plastic-doctor", out
  end

  def test_warn_yields_binary_error_line
    health = { status: "warn", checks: [{ name: "version_match", status: "warn", message: "mismatch" }] }
    out = BootBanner.render(health: health, version: "1.2.3")
    assert_equal "Plastic Core loaded — v1.2.3 | doctor --core run: error — run /plastic-doctor", out
  end

  def test_non_pass_with_no_checks_yields_binary_error_line
    health = { status: "fail", checks: [] }
    out = BootBanner.render(health: health, version: "1.2.3")
    assert_equal "Plastic Core loaded — v1.2.3 | doctor --core run: error — run /plastic-doctor", out
  end

  def test_nil_health_yields_binary_error_line
    out = BootBanner.render(health: nil, version: "1.2.3")
    assert_equal "Plastic Core loaded — v1.2.3 | doctor --core run: error — run /plastic-doctor", out
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
    assert_includes ctx, "doctor --core run:"
    assert_includes ctx, "run /plastic-doctor"
  end

  # Intent 54: the boot banner must be user-visible, carried on the top-level
  # systemMessage channel (additionalContext is model-only). It must match the
  # first line of additionalContext so the two channels cannot drift.
  def test_emits_visible_system_message_matching_banner
    out, _err, status = run_hook
    assert_equal 0, status.exitstatus
    msg = JSON.parse(out)["systemMessage"]
    refute_nil msg, "hook must emit a top-level systemMessage banner"
    assert_includes msg, "Plastic Core loaded"
    first_line = context_from(out).lines.first.strip
    assert_equal first_line, msg.strip, "systemMessage must match additionalContext banner line"
  end

  # Intent 45a: the QMD status line is READ-ONLY and report-only. The hook calls
  # QmdSync with the host's real PATH, so we cannot force qmd present/absent
  # deterministically. What we CAN assert unconditionally: the hook exits 0 and
  # emits parseable JSON regardless of qmd state, and if a QMD line surfaces it
  # lives only in additionalContext (model channel), never in systemMessage.
  def test_qmd_line_is_report_only_and_never_blocks
    out, _err, status = run_hook
    assert_equal 0, status.exitstatus, "qmd status must never block session start"
    payload = JSON.parse(out) # must be parseable
    ctx = payload.dig("hookSpecificOutput", "additionalContext")
    msg = payload["systemMessage"].to_s
    refute_includes msg, "QMD", "QMD status must never leak into the visible systemMessage"
    if ctx.include?("QMD")
      assert(ctx.include?("Plastic collections indexed") || ctx.include?("qmd-sync register --all"),
             "QMD line, when present, must be one of the two known states")
    end
  end
end

# Intent 45a: unit-level coverage of the three-state line construction, driving
# QmdSync.status with an injected runner/detector so it is hermetic (no real qmd,
# no PATH dependency). Mirrors the branch logic the hook applies.
class QmdStatusLineTest < Minitest::Test
  def line_for(status)
    return nil unless status[:present]
    if status[:all_registered]
      "QMD: #{status[:registered].size} Plastic collections indexed (search with the qmd skill)."
    else
      "QMD detected — run `qmd-sync register --all` to index your Plastic stores for search."
    end
  end

  def test_absent_yields_no_line
    status = QmdSync.status(plastic_home: "/nope", detector: -> { false })
    assert_nil line_for(status)
  end

  def test_all_registered_yields_indexed_line
    runner = ->(args) { ["plastic-global (qmd://plastic-global/)\n", true] }
    Dir.mktmpdir do |home|
      status = QmdSync.status(plastic_home: home, runner: runner, detector: -> { true })
      assert_equal "QMD: 1 Plastic collections indexed (search with the qmd skill).", line_for(status)
    end
  end

  def test_missing_collections_yields_setup_nudge
    runner = ->(args) { ["No collections\n", true] }
    Dir.mktmpdir do |home|
      status = QmdSync.status(plastic_home: home, runner: runner, detector: -> { true })
      assert_equal "QMD detected — run `qmd-sync register --all` to index your Plastic stores for search.",
                   line_for(status)
    end
  end
end
