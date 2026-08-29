require "minitest/autorun"
require "tmpdir"
require "json"
require "fileutils"
require "open3"

require_relative "../scripts/lib/boot_banner"
require_relative "../scripts/lib/qmd_sync"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/session_ledger"

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
    # PLASTIC_TMP + session isolation (intent 108): with an active intent in
    # INDEX the hook derives (writes) a bridge; keep even the empty-INDEX
    # smoke run away from the live /tmp and session id.
    Open3.capture3({ "PLASTIC_TMP" => @dir, "CLAUDE_CODE_SESSION_ID" => nil },
                   "ruby", HOOK, @index, @dir, "global")
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

# Intent 231: Plastic home and the store are two different paths. hooks/session-start
# passes home (~/.plastic) as argument 2, so the hook itself must compose the store
# before handing anything to Bridge.derive. No test reached this path before: the
# SessionStartHookTest fixture above seeds an EMPTY "## Active" section, so the
# active.length == 1 guard never fires and the bridge is never derived. These tests
# seed a real Active entry and read the bridge the hook actually wrote.
#
# Hermetic per test/hermeticity_guard_test.rb: PLASTIC_TMP points the bridge write at
# a private tmpdir, and CLAUDE_CODE_SESSION_ID is cleared so the hook keys the bridge
# by its own pid and never touches a live session's file.
class SessionStartBridgePathTest < Minitest::Test
  HOOK = File.expand_path("../scripts/hook-session-start", __dir__)
  SHIM = File.expand_path("../hooks/session-start", __dir__)
  DIR_NAME = "231--session-start-home-vs-store".freeze

  def setup
    @home = Dir.mktmpdir("plastic-231-home")
    @tmp = Dir.mktmpdir("plastic-231-tmp")
    @intent_dir = File.join(@home, "store", DIR_NAME)
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@home, "INDEX.md"),
               "# Index\n\n## Active\n" \
               "- [231 - session start home vs store](store/#{DIR_NAME}/#{DIR_NAME}.md)\n" \
               "\n## Future\n")
    File.write(File.join(@intent_dir, "#{DIR_NAME}.md"),
               "---\nid: \"231\"\n---\n\n## Intent\nHome and store are two paths.\n")
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@tmp)
  end

  # Argument 2 is Plastic HOME, exactly what hooks/session-start passes today.
  def run_hook
    Open3.capture3({ "PLASTIC_TMP" => @tmp, "CLAUDE_CODE_SESSION_ID" => nil },
                   "ruby", HOOK, File.join(@home, "INDEX.md"), @home, "global")
  end

  def bridge_files
    Dir[File.join(@tmp, "plastic-*.json")]
  end

  def bridge
    files = bridge_files
    assert_equal 1, files.length, "hook must write exactly one bridge"
    JSON.parse(File.read(files.first))
  end

  def test_bridge_store_field_is_the_store_not_home
    _out, _err, status = run_hook
    assert_equal 0, status.exitstatus
    data = bridge
    assert_equal File.join(@home, "store"), data.dig("intent", "store"),
                 "bridge must record the store path, not Plastic home"
    refute_equal @home, data.dig("intent", "store"),
                 "Plastic home must never be written as the bridge store field"
  end

  def test_bridge_dir_field_is_the_bare_intent_dir_name
    run_hook
    data = bridge
    assert_equal DIR_NAME, data.dig("intent", "dir")
    refute_includes data.dig("intent", "dir"), "store/",
                    "dir is relative to the store, so it carries no store/ prefix"
  end

  def test_no_doubled_store_segment_is_ever_constructed
    run_hook
    data = bridge
    refute_includes data.dig("intent", "store"), "store/store"
    assert_equal @intent_dir, Bridge.bridge_intent_dir(data),
                 "store plus dir must recompose to the real intent directory"
    refute_includes Bridge.bridge_intent_dir(data), "store/store"
  end

  # The tempting one-line repair is to make the shim pass $HOME/.plastic/store. That
  # is the wrong fix: ten other lines in the hook compose store/ onto argument 2, so
  # it would produce store/store paths. Pin the shim so that repair cannot land quietly.
  def test_shim_passes_plastic_home_not_the_store
    src = File.read(SHIM)
    assert_includes src, '"$HOME/.plastic" "global"',
                    "shim must keep passing Plastic home as argument 2"
    refute_includes src, "$HOME/.plastic/store",
                    "the split belongs inside the hook, never in the shim"
  end

  # Intent 230 split Bridge.derive into a pure derive_data plus a writing derive, and
  # kept session start on the writing form on purpose. Both halves of that contract.
  def test_bridge_is_persisted_immediately
    _out, _err, status = run_hook
    assert_equal 0, status.exitstatus
    assert_equal 1, bridge_files.length,
                 "session start persists the bridge on the spot (intent 230 contract)"
  end

  def test_hook_still_calls_the_writing_derive
    src = File.read(HOOK)
    assert_includes src, "Bridge.derive(session,",
                    "session start must keep the writing derive, not derive_data"
  end

  # The cost of the bug: intent_active? resolves the INDEX as the PARENT of the store
  # dir, so a bridge carrying home looks inactive and purge_done_bridges deletes a live
  # session's bridge. The second assertion is the negative control that pins the old
  # failure mode.
  def test_purge_sees_a_live_active_intent_as_active
    run_hook
    data = bridge
    assert Bridge.intent_active?("231", store: data.dig("intent", "store")),
           "a live Active intent's bridge must survive purge_done_bridges"
    refute Bridge.intent_active?("231", store: @home),
           "home as the store field is what made a live intent look inactive"
  end
end

# Intent 298, spec D4: hook-session-start opens or joins the day ledger and
# writes the per-session pointer and heartbeat. Hermetic: PLASTIC_TMP isolates
# the bridge write and CLAUDE_CODE_SESSION_ID is set explicitly per test.
class SessionStartDayLedgerTest < Minitest::Test
  HOOK = File.expand_path("../scripts/hook-session-start", __dir__)

  def setup
    @home = Dir.mktmpdir("session-start-ledger-home")
    @tmp = Dir.mktmpdir("session-start-ledger-tmp")
    @index = File.join(@home, "INDEX.md")
    File.write(@index, "# Index\n\n## Active\n\n## Future\n")
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@tmp)
  end

  def store
    File.join(@home, "store")
  end

  def run_hook(session_id: "sess-boot")
    Open3.capture3({ "PLASTIC_TMP" => @tmp, "CLAUDE_CODE_SESSION_ID" => session_id },
                   "ruby", HOOK, @index, @home, "global")
  end

  def test_first_boot_creates_day_file_writes_pointer_and_heartbeat
    day = SessionLedger.day_id
    out, _err, status = run_hook(session_id: "sess-boot-1")
    assert_equal 0, status.exitstatus

    assert File.exist?(SessionLedger.day_file(store, day)), ".sessions/<day>/<day>.md must be created"

    sid = SessionLedger.short_session_id(nil, "sess-boot-1")
    pointer = SessionLedger.pointer_path(store, sid)
    assert File.exist?(pointer), "the per-session pointer must be written"
    assert_equal day, File.read(pointer).strip, "current must be today's day id on first boot"
    assert File.exist?(SessionLedger.heartbeat_path(store, sid)), "the heartbeat must be written"

    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext")
    assert_includes ctx, "day ledger #{day} joined"
  end

  def test_second_boot_joins_current_untouched_and_counts_are_correct
    day = SessionLedger.day_id
    run_hook(session_id: "sess-boot-2") # first boot: scaffolds the day and writes current

    SessionLedger.append_line(SessionLedger.checklist_path(store, day),
                               SessionLedger.checklist_line(:open, "aaaaaaaa", "global", "An open item"),
                               header: SessionLedger.checklist_header(day))
    SessionLedger.append_line(SessionLedger.checklist_path(store, day),
                               SessionLedger.checklist_line(:pending, "aaaaaaaa", "global", "A pending item"),
                               header: nil)

    sid = SessionLedger.short_session_id(nil, "sess-boot-2")
    pointer = SessionLedger.pointer_path(store, sid)
    before = File.read(pointer)

    out, _err, status = run_hook(session_id: "sess-boot-2") # second boot: joins
    assert_equal 0, status.exitstatus
    assert_equal before, File.read(pointer), "current must be untouched on a second boot"

    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext")
    assert_includes ctx, "1 open items, 1 pending"
  end

  def test_current_already_naming_an_intent_is_left_as_is
    sid = SessionLedger.short_session_id(nil, "sess-boot-3")
    FileUtils.mkdir_p(SessionLedger.session_tmp_dir(store, sid))
    File.write(SessionLedger.pointer_path(store, sid), "42--some-intent\n")

    out, _err, status = run_hook(session_id: "sess-boot-3")
    assert_equal 0, status.exitstatus, out
    assert_equal "42--some-intent", File.read(SessionLedger.pointer_path(store, sid)).strip,
                 "current already names an intent; session-start must not overwrite it"
  end

  # hook-session-start takes its inputs as positional ARGV, never stdin, so this
  # proves it boots cleanly with nothing on stdin at all and still derives a
  # session id (env cleared here, so from the hook's own Process.pid).
  def test_no_stdin_still_derives_a_session_id_and_exits_zero
    out, _err, status = Open3.capture3({ "PLASTIC_TMP" => @tmp, "CLAUDE_CODE_SESSION_ID" => nil },
                                        "ruby", HOOK, @index, @home, "global")
    assert_equal 0, status.exitstatus
    assert JSON.parse(out)

    entries = Dir.exist?(SessionLedger.tmp_root(store)) ? Dir.children(SessionLedger.tmp_root(store)) : []
    refute_empty entries, "a session id must be derived from env or the hook's own pid, never skipped"
  end
end
