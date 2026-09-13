require "minitest/autorun"
require "tmpdir"
require "json"
require "fileutils"
require "open3"

require_relative "../scripts/lib/boot_banner"
require_relative "../scripts/lib/qmd_sync"
require_relative "../scripts/lib/savepoint"
require_relative "../scripts/lib/index_entry"
require_relative "../scripts/lib/session_ledger"
require_relative "../scripts/lib/packet_wrapper"

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

  # --- QMD hits wrapped as untrusted data (intent 341, G8, C23) --------------------

  # A fake `qmd` on a PATH-only bindir, prepended onto the real PATH so `ruby`
  # itself still resolves. Guarantees the "all registered" QMD line fires
  # deterministically, regardless of the host's own qmd state.
  def bindir_with_fake_qmd
    bindir = Dir.mktmpdir("session-start-qmd-bin")
    fake = File.join(bindir, "qmd")
    File.write(fake, <<~RUBY)
      #!/usr/bin/env ruby
      puts "plastic-global (qmd://plastic-global/)"
    RUBY
    File.chmod(0o755, fake)
    bindir
  end

  def run_hook_with_path(path_prefix)
    Open3.capture3({ "PLASTIC_TMP" => @dir, "CLAUDE_CODE_SESSION_ID" => nil,
                      "PATH" => [path_prefix, ENV.fetch("PATH", "")].join(File::PATH_SEPARATOR) },
                   "ruby", HOOK, @index, @dir, "global")
  end

  def strip_wrapped_blocks(text)
    text.gsub(/<<<PLASTIC-DATA:[0-9a-f]+ label="[^"]*" source="[^"]*">>>\n.*?<<<END-PLASTIC-DATA:[0-9a-f]+>>>\n?/m, "")
  end

  def test_qmd_hits_are_wrapped_with_the_packet_wrapper
    bindir = bindir_with_fake_qmd
    out, _err, status = run_hook_with_path(bindir)
    assert_equal 0, status.exitstatus

    ctx = context_from(out)
    blocks = PacketWrapper.unwrap(ctx)
    qmd_block = blocks.find { |b| b[:label] == "qmd-hit" }
    refute_nil qmd_block, "the QMD status line must be wrapped in a data block"
    assert_includes qmd_block[:payload], "Plastic collections indexed"
  ensure
    FileUtils.rm_rf(bindir) if bindir
  end

  def test_banners_stay_unwrapped
    bindir = bindir_with_fake_qmd
    out, _err, status = run_hook_with_path(bindir)
    assert_equal 0, status.exitstatus

    ctx = context_from(out)
    assert_includes ctx, "Plastic collections indexed", "fixture sanity: the fake qmd must yield the indexed line"

    residual = strip_wrapped_blocks(ctx)
    assert_includes residual, "Plastic Core loaded", "the core banner must survive outside every data block"
    refute_includes residual, "Plastic collections indexed",
                     "the QMD line must live only inside a data block, never loose too"
  ensure
    FileUtils.rm_rf(bindir) if bindir
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
# before reading the single Active intent. Since intent 307 the hook derives the stage
# line from the intent directory's files (Savepoint) and writes no bridge at all.
#
# Hermetic per test/hermeticity_guard_test.rb: PLASTIC_TMP and CLAUDE_CODE_SESSION_ID
# are set explicitly so nothing keys off the live session.
class SessionStartStagePathTest < Minitest::Test
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
    # The banner branch that carries the stage line runs only when the core
    # conventions file is present beside INDEX.md.
    File.write(File.join(@home, "PLASTIC.md"), "# Plastic: Conventions\n")
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

  def context
    out, _err, status = run_hook
    assert_equal 0, status.exitstatus
    JSON.parse(out).dig("hookSpecificOutput", "additionalContext")
  end

  # Intent 341, G8: the stage line was doctrine ceremony (a skill deriving
  # the same stage by reading the intent directory already carries it) and
  # is cut from the live boot. Savepoint.derive_stage itself is untouched
  # (still callable, still correct); only the hook stops printing its result.
  def test_stage_line_is_no_longer_printed_at_boot
    refute_includes context, "Stage: ", "the stage line is ceremony the hook no longer prints (intent 341)"
    assert_equal Savepoint.derive_stage(@intent_dir), Savepoint.derive_stage(@intent_dir),
                 "Savepoint.derive_stage itself stays callable; only the hook's print is cut"
  end

  def test_no_bridge_file_is_written
    run_hook
    assert_empty Dir[File.join(@tmp, "plastic-*.json")], "the /tmp bridge was removed in 2.0 (intent 307)"
  end

  def test_hook_no_longer_derives_a_bridge
    src = File.read(HOOK)
    refute_includes src, "Bridge.derive"
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

  # intent_active? resolves the INDEX as the PARENT of the store dir; home as the store
  # is what once made a live intent look inactive.
  def test_intent_active_resolves_the_index_from_the_store_not_home
    assert IndexEntry.active?("231", store: File.join(@home, "store"))
    refute IndexEntry.active?("231", store: @home)
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

  # 344 n2 (D4): session start creates the tmp directory and the heartbeat,
  # and stops writing the retired per-session pointer altogether.
  def test_session_start_writes_heartbeat_and_no_pointer
    day = SessionLedger.day_id
    out, _err, status = run_hook(session_id: "sess-boot-1")
    assert_equal 0, status.exitstatus

    assert File.exist?(SessionLedger.day_file(store, day)), ".sessions/<day>/<day>.md must be created"

    sid = SessionLedger.short_session_id(nil, "sess-boot-1")
    assert File.exist?(SessionLedger.heartbeat_path(store, sid)), "the heartbeat must be written"
    refute File.exist?(File.join(SessionLedger.session_tmp_dir(store, sid), "current")), "the retired pointer must never be written"

    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext")
    assert_includes ctx, "day ledger #{day} joined"
  end

  def test_second_boot_joins_and_counts_are_correct
    day = SessionLedger.day_id
    run_hook(session_id: "sess-boot-2") # first boot: scaffolds the day and the tmp dir

    SessionLedger.append_line(SessionLedger.checklist_path(store, day),
                               SessionLedger.checklist_line(:open, "aaaaaaaa", "global", "An open item"),
                               header: SessionLedger.checklist_header(day))
    SessionLedger.append_line(SessionLedger.checklist_path(store, day),
                               SessionLedger.checklist_line(:pending, "aaaaaaaa", "global", "A pending item"),
                               header: nil)

    sid = SessionLedger.short_session_id(nil, "sess-boot-2")
    tmp_dir = SessionLedger.session_tmp_dir(store, sid)
    assert Dir.exist?(tmp_dir), "the first boot must create the session tmp directory"

    out, _err, status = run_hook(session_id: "sess-boot-2") # second boot: joins
    assert_equal 0, status.exitstatus
    assert Dir.exist?(tmp_dir), "the second boot must not remove the session tmp directory"
    refute File.exist?(File.join(SessionLedger.session_tmp_dir(store, sid), "current")), "the retired pointer must never be written"

    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext")
    assert_includes ctx, "1 open items, 1 pending"
  end

  # --- the day summary (intent 311, spec D8) ------------------------------------------

  def summary_of(ctx)
    ctx.split("Day summary ", 2).last.to_s
  end

  def test_first_boot_on_an_empty_day_injects_the_joined_line_and_no_summary
    out, _err, status = run_hook(session_id: "sess-boot-4")
    assert_equal 0, status.exitstatus
    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext")
    assert_includes ctx, "day ledger #{SessionLedger.day_id} joined"
    refute_includes ctx, "Day summary"
  end

  def test_boot_injects_the_four_part_day_summary_after_the_joined_line
    day = SessionLedger.day_id
    run_hook(session_id: "sess-boot-5")
    checklist = SessionLedger.checklist_path(store, day)
    SessionLedger.append_line(checklist, SessionLedger.checklist_line(:open, "aaaaaaaa", "global", "An open item"),
                              header: SessionLedger.checklist_header(day))
    SessionLedger.append_line(checklist, SessionLedger.checklist_line(:pending, "bbbbbbbb", "global", "A pending item"),
                              header: nil)
    SessionLedger.append_line(SessionLedger.savepoint_path(store, day),
                              SessionLedger.savepoint_line("Done", "aaaaaaaa", "global", "Something finished", now: Time.now),
                              header: nil)

    dir = File.join(store, "231--live-intent")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "231--live-intent.md"), "---\nid: \"231\"\n---\n")
    File.write(@index, "# Index\n\n## Active\n- [231 - Live](store/231--live-intent/231--live-intent.md) - t\n\n## Future\n")
    File.write(File.join(dir, "savepoint.md"), "2026-08-30T09:00:00Z  Exec  executor running\n")
    lock = File.join(dir, "delivery.lock")
    File.write(lock, JSON.generate("type" => "delivery", "owner_session" => "x", "run_mode" => "auto"))

    other = "cccccccc"
    FileUtils.mkdir_p(SessionLedger.session_tmp_dir(store, other))
    File.write(SessionLedger.heartbeat_path(store, other), "#{Time.now.utc.iso8601}\n")

    out, _err, status = run_hook(session_id: "sess-boot-5")
    assert_equal 0, status.exitstatus
    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext")
    joined = "day ledger #{day} joined (1 open items, 1 pending)"
    assert_includes ctx, joined
    assert_operator ctx.index(joined), :<, ctx.index("Day summary #{day}:")
    summary = summary_of(ctx)
    assert_includes summary, "Open:"
    assert_includes summary, "- [aaaaaaaa] [global] An open item"
    assert_includes summary, "Done, last five:"
    assert_includes summary, "Something finished"
    assert_includes summary, "Live auto intents:"
    assert_includes summary, "- 231 live-intent: 2026-08-30T09:00:00Z  Exec  executor running"
    assert_includes summary, "Other active sessions:"
    assert_includes summary, "- #{other} ("
    refute_includes summary, SessionLedger.short_session_id(nil, "sess-boot-5")
    summary.each_line do |line|
      refute_match(/\A- \[[ ~x>\-^]\] \[/, line, "raw ledger line injected: #{line.inspect}")
    end
  end

  # hook-session-start takes its main inputs as positional ARGV; this proves it
  # boots cleanly with nothing usable on stdin either (env cleared here, so the
  # session id falls all the way back to the hook's own Process.pid, spec D4
  # row G3).
  def test_no_stdin_still_derives_a_session_id_and_exits_zero
    out, _err, status = Open3.capture3({ "PLASTIC_TMP" => @tmp, "CLAUDE_CODE_SESSION_ID" => nil },
                                        "ruby", HOOK, @index, @home, "global")
    assert_equal 0, status.exitstatus
    assert JSON.parse(out)

    entries = Dir.exist?(SessionLedger.tmp_root(store)) ? Dir.children(SessionLedger.tmp_root(store)) : []
    refute_empty entries, "a session id must be derived from env or the hook's own pid, never skipped"
  end

  # --- row G: the stdin payload's session_id (spec 298 D1, spec D4) -----------------

  def run_hook_with_stdin(stdin_data:, env_session_id: nil)
    env = { "PLASTIC_TMP" => @tmp, "CLAUDE_CODE_SESSION_ID" => env_session_id }
    Open3.capture3(env, "ruby", HOOK, @index, @home, "global", stdin_data: stdin_data)
  end

  def test_g1_prefers_the_payloads_session_id_over_a_different_env_var
    payload = JSON.generate("session_id" => "payload-sid-g1")
    out, _err, status = run_hook_with_stdin(stdin_data: payload, env_session_id: "env-sid-g1")
    assert_equal 0, status.exitstatus
    assert JSON.parse(out)

    sid = SessionLedger.short_session_id(nil, "payload-sid-g1")
    other_sid = SessionLedger.short_session_id(nil, "env-sid-g1")
    assert Dir.exist?(SessionLedger.session_tmp_dir(store, sid)),
           "the tmp dir must be created under the payload's session id"
    refute Dir.exist?(SessionLedger.session_tmp_dir(store, other_sid)),
           "the env var's session id must not be used when the payload names one"
  end

  def test_g2_falls_back_to_the_env_var_when_the_payload_carries_no_id
    payload = JSON.generate("prompt" => "irrelevant, no session_id key at all")
    out, _err, status = run_hook_with_stdin(stdin_data: payload, env_session_id: "env-sid-g2")
    assert_equal 0, status.exitstatus
    assert JSON.parse(out)

    sid = SessionLedger.short_session_id(nil, "env-sid-g2")
    assert Dir.exist?(SessionLedger.session_tmp_dir(store, sid)),
           "the env var must be used when the stdin payload names no session_id"
  end

  def test_g3_falls_back_to_the_pid_with_no_payload_and_no_env_var
    env = { "PLASTIC_TMP" => @tmp, "CLAUDE_CODE_SESSION_ID" => nil }
    child_pid = nil
    out = nil
    status = nil
    Open3.popen3(env, "ruby", HOOK, @index, @home, "global") do |stdin, stdout, _stderr, wait_thr|
      child_pid = wait_thr.pid
      stdin.write("not valid json{{{")
      stdin.close
      out = stdout.read
      status = wait_thr.value
    end
    assert_equal 0, status.exitstatus
    assert JSON.parse(out)

    expected_sid = SessionLedger.short_session_id(nil, child_pid.to_s)
    assert Dir.exist?(SessionLedger.session_tmp_dir(store, expected_sid)),
           "with no payload id and no env var, the session must be keyed by the hook's own pid " \
           "(#{expected_sid}), not skipped or left to some other fallback"
  end

  def test_g4_the_stdin_read_never_blocks_on_a_terminal
    require "pty"
    require "timeout"

    out = +""
    PTY.spawn({ "PLASTIC_TMP" => @tmp, "CLAUDE_CODE_SESSION_ID" => "sess-tty-guard" },
              "ruby", HOOK, @index, @home, "global", err: File::NULL) do |r, _w, spawned_pid|
      begin
        Timeout.timeout(5) do
          loop { out << r.readpartial(4096) }
        end
      rescue EOFError
        nil
      end
      begin
        Process.wait(spawned_pid)
      rescue Errno::ECHILD
        nil
      end
    end
    assert JSON.parse(out), "the hook must still emit valid JSON when stdin is a tty"
  rescue Errno::EIO
    assert JSON.parse(out), "the hook must still emit valid JSON when stdin is a tty"
  end
end

# Intent 355 spec D9, node n7 (review fix n8, B6): a subagent needs the core
# banner only. The stdin payload's agent_id alone marks a subagent
# SessionStart call; agent_type is carried by a live `claude --agent` session
# too, so agent_type without agent_id is a live session, not a subagent. An
# absent agent_id is a live session, and the marker is read only from that
# payload, never from an environment variable. Fixture carries an active
# intent and a stale future intent behind PLASTIC.md so a live boot's full
# content (Active intents, Stale future intents, day ledger) has something to
# suppress; a fixture without that content would leave the suppression
# unproven either way.
class SessionStartSubagentTest < Minitest::Test
  HOOK = File.expand_path("../scripts/hook-session-start", __dir__)

  def setup
    @home = Dir.mktmpdir("session-start-subagent-home")
    @tmp = Dir.mktmpdir("session-start-subagent-tmp")
    @index = File.join(@home, "INDEX.md")
    File.write(File.join(@home, "PLASTIC.md"), "# Plastic: Conventions\n")

    active_dir = File.join(@home, "store", "555--an-active-intent")
    FileUtils.mkdir_p(active_dir)
    File.write(File.join(active_dir, "555--an-active-intent.md"),
               "---\nid: \"555\"\n---\n\n## Intent\nActive.\n")

    stale_dir = File.join(@home, "store", "556--a-stale-intent")
    FileUtils.mkdir_p(stale_dir)
    File.write(File.join(stale_dir, "556--a-stale-intent.md"),
               "---\nid: \"556\"\ncreated: '2000-01-01'\n---\n\n## Intent\nStale.\n")

    File.write(@index, <<~MD)
      # Index

      ## Active
      - [555 - An active intent](store/555--an-active-intent/555--an-active-intent.md)

      ## Future
      - [556 - A stale intent](store/556--a-stale-intent/556--a-stale-intent.md)
    MD
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@tmp)
  end

  def run_hook(stdin_data:, session_id: "sess-subagent")
    env = { "PLASTIC_TMP" => @tmp, "CLAUDE_CODE_SESSION_ID" => session_id }
    Open3.capture3(env, "ruby", HOOK, @index, @home, "global", stdin_data: stdin_data)
  end

  # Row 7.1
  def test_subagent_session_boot_is_core_banner_only
    payload = JSON.generate("session_id" => "sub-1", "agent_id" => "agent-42")
    out, _err, status = run_hook(stdin_data: payload)
    assert_equal 0, status.exitstatus
    parsed = JSON.parse(out)
    ctx = parsed.dig("hookSpecificOutput", "additionalContext")
    banner = parsed["systemMessage"]

    assert_equal "#{banner}\n", ctx,
                 "a subagent boot must emit the core banner and nothing else"
    refute_includes ctx, "Active intents"
    refute_includes ctx, "Stale future intents"
    refute_includes ctx, "day ledger"
  end

  # Row 7.2
  def test_missing_subagent_marker_is_a_live_session
    payload = JSON.generate("session_id" => "live-1")
    out, _err, status = run_hook(stdin_data: payload)
    assert_equal 0, status.exitstatus
    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext")

    assert_includes ctx, "Active: [555 — 555 - An active intent]"
    assert_includes ctx, "day ledger"
  end

  # Row 7.3
  def test_marker_read_from_hook_input
    env_with_stray_agent_env = { "PLASTIC_TMP" => @tmp, "CLAUDE_CODE_SESSION_ID" => "sess-env-only",
                                  "CLAUDE_AGENT_ID" => "agent-from-env-must-be-ignored" }
    payload_without_marker = JSON.generate("session_id" => "sess-env-only")
    out, _err, status = Open3.capture3(env_with_stray_agent_env, "ruby", HOOK, @index, @home, "global",
                                        stdin_data: payload_without_marker)
    assert_equal 0, status.exitstatus
    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext")
    assert_includes ctx, "Active: [555 — 555 - An active intent]",
                    "an agent id carried only on the env, never on stdin, must never mark a subagent session"

    payload_with_marker = JSON.generate("session_id" => "sess-marker-only", "agent_id" => "agent-42")
    out2, _err2, status2 = run_hook(stdin_data: payload_with_marker, session_id: "sess-marker-only")
    assert_equal 0, status2.exitstatus
    ctx2 = JSON.parse(out2).dig("hookSpecificOutput", "additionalContext")
    refute_includes ctx2, "Active: [555",
                    "the marker on the stdin payload alone, with no env support at all, must still mark a subagent"
  end

  # Row 7.2 (B6): a live `claude --agent` session carries agent_type but no
  # agent_id (only a spawned subagent carries agent_id). Reading agent_type
  # as the marker would boot a live agent session with the core banner only.
  def test_agent_type_without_agent_id_is_a_live_session
    payload = JSON.generate("session_id" => "live-agent-type-only", "agent_type" => "executor")
    out, _err, status = run_hook(stdin_data: payload, session_id: "live-agent-type-only")
    assert_equal 0, status.exitstatus
    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext")

    assert_includes ctx, "Active: [555 — 555 - An active intent]",
                     "agent_type alone, with no agent_id, must be a live session, not a subagent"
  end

  # Row 7.6
  def test_subagent_branch_exception_degrades_to_banner
    payload = JSON.generate("session_id" => "sub-weird", "agent_id" => { "nested" => ["weird", 1, nil] })
    out, _err, status = run_hook(stdin_data: payload, session_id: "sess-subagent-weird")
    assert_equal 0, status.exitstatus
    parsed = JSON.parse(out)
    assert_includes parsed["systemMessage"], "Plastic Core loaded"
    ctx = parsed.dig("hookSpecificOutput", "additionalContext")
    assert_includes ctx, "Plastic Core loaded"
    refute_includes ctx, "Active:",
                    "a malformed marker value must still degrade to a banner-only boot, never crash to nothing"
  end
end

# Intent 341, G8 (node n2), row 2.1: session start stops dumping doctrine. A
# live boot carries the core banner, the project (or global) banner with its
# one active intent, and the QMD line; the conventions dump, the bulleted
# active-intents listing, the stage line, and the stale-future paragraph are
# all cut (a skill or the conventions chapter already carries that text).
# Deprecation warnings, the update notice, the sweep line and the day-ledger
# line are unrelated bookkeeping this cut does not touch, so this fixture
# carries none of them and the assertions below do not need to exclude them.
class SessionStartDoctrineCutTest < Minitest::Test
  HOOK = File.expand_path("../scripts/hook-session-start", __dir__)

  def setup
    @home = Dir.mktmpdir("session-start-doctrine-cut-home")
    @tmp = Dir.mktmpdir("session-start-doctrine-cut-tmp")
    @index = File.join(@home, "INDEX.md")

    File.write(File.join(@home, "PLASTIC.md"), <<~MD)
      # Plastic: Conventions

      THIS CONVENTIONS PROSE PARAGRAPH MUST NEVER REACH A LIVE BOOT.
    MD

    active_dir = File.join(@home, "store", "701--an-active-intent")
    FileUtils.mkdir_p(active_dir)
    File.write(File.join(active_dir, "701--an-active-intent.md"),
               "---\nid: \"701\"\n---\n\n## Intent\nActive.\n")

    stale_dir = File.join(@home, "store", "702--a-stale-intent")
    FileUtils.mkdir_p(stale_dir)
    File.write(File.join(stale_dir, "702--a-stale-intent.md"),
               "---\nid: \"702\"\ncreated: '2000-01-01'\n---\n\n## Intent\nStale.\n")

    File.write(@index, <<~MD)
      # Index

      ## Active
      - [701 - An active intent](store/701--an-active-intent/701--an-active-intent.md)

      ## Future
      - [702 - A stale intent](store/702--a-stale-intent/702--a-stale-intent.md)
    MD
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@tmp)
  end

  def context
    out, _err, status = Open3.capture3({ "PLASTIC_TMP" => @tmp, "CLAUDE_CODE_SESSION_ID" => "sess-doctrine-cut" },
                                        "ruby", HOOK, @index, @home, "global")
    assert_equal 0, status.exitstatus
    JSON.parse(out).dig("hookSpecificOutput", "additionalContext")
  end

  # Row 2.1
  def test_live_session_boot_carries_banners_only
    ctx = context

    assert_includes ctx, "Plastic Core loaded", "the core banner must still boot"
    assert_includes ctx, "Active: [701 — 701 - An active intent]",
                    "the project/global banner keeps its one active intent"

    refute_includes ctx, "CONVENTIONS PROSE", "PLASTIC.md's conventions dump must not reach a live boot"
    refute_includes ctx, "Active intents:", "the bulleted active-intents listing is cut"
    refute_includes ctx, "No active intents", "the no-active-intent nudge is cut"
    refute_includes ctx, "Stale future intents", "the stale-future paragraph is cut"
    refute_includes ctx, "Stage: ", "the stage line is cut"
  end
end

# Intent 341, G8 (node n2), row 2.4: the cut must not introduce a raise path
# that boots a live session with nothing. hook-session-start now computes the
# core banner before anything that reads INDEX.md, projects.yml, or
# PLASTIC.md, and wraps that entire best-effort assembly in one rescue that
# falls back to a banner-only boot. A malformed projects.yml (a project entry
# that is not a mapping, so `info["path"]` blows up trying to build a
# `File.expand_path` argument) is a real, reachable, hermetic way to raise
# partway through that assembly.
class SessionStartBannerExceptionTest < Minitest::Test
  HOOK = File.expand_path("../scripts/hook-session-start", __dir__)

  def setup
    @home = Dir.mktmpdir("session-start-banner-exception-home")
    @tmp = Dir.mktmpdir("session-start-banner-exception-tmp")
    @index = File.join(@home, "INDEX.md")
    File.write(@index, "# Index\n\n## Active\n\n## Future\n")
    File.write(File.join(@home, "PLASTIC.md"), "# Plastic: Conventions\n")
    # "broken" maps to an Integer, not a Hash: info["path"] then raises
    # TypeError (Integer#[] takes no implicit String), reachable before the
    # project/global banner is ever built.
    File.write(File.join(@home, "projects.yml"), "projects:\n  broken: 12345\n")
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@tmp)
  end

  def run_hook
    Open3.capture3({ "PLASTIC_TMP" => @tmp, "CLAUDE_CODE_SESSION_ID" => "sess-banner-exception" },
                   "ruby", HOOK, @index, @home, "global")
  end

  def test_exception_degrades_to_banner
    out, err, status = run_hook

    assert_equal 0, status.exitstatus, "a raise anywhere in the best-effort assembly must still exit 0: #{err}"
    assert_empty err.strip, "the rescue must swallow the exception, never leak a backtrace to stderr"

    parsed = JSON.parse(out)
    assert_includes parsed["systemMessage"], "Plastic Core loaded"
    ctx = parsed.dig("hookSpecificOutput", "additionalContext")
    assert_includes ctx, "Plastic Core loaded", "the boot must degrade to the banner, never to nothing"
    refute_includes ctx, "Active:", "a failed assembly must not leak a partial banner line"
  end
end

# Intent 340a, G7b, n3, rows 3.7-3.11: hook-session-start gains one
# unrecorded watch tick (RunnerWatch.tick(..., record: false)) per intent
# ActiveDelivery.candidate_intent_dirs finds, naming every stalled or
# done_unreported one in a single line, nothing when there is none.
# Hermetic: project_roots is pinned to [] under this fixture's own
# plastic_home so the walk never leaves this tmp home; record: false means
# a boot must never write the fixture's own watch.state or watch.record.
class SessionStartWatchTest < Minitest::Test
  HOOK = File.expand_path("../scripts/hook-session-start", __dir__)
  PLUGIN_ROOT = File.expand_path("..", __dir__)

  MATRIX = <<~MD
    | Operation | Failure mode | Test |
    | --- | --- | --- |
    | op | mode | a test |
  MD

  def setup
    @home = Dir.mktmpdir("session-start-watch-home")
    @tmp = Dir.mktmpdir("session-start-watch-tmp")
    @index = File.join(@home, "INDEX.md")
    File.write(@index, "# Index\n\n## Active\n\n## Future\n")
    File.write(File.join(@home, "PLASTIC.md"), "# Plastic: Conventions\n")
    File.write(File.join(@home, "config.yml"), "version: 3\nproject_roots: []\n")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@tmp)
  end

  def run_hook(stdin_data: "", session_id: "sess-watch")
    env = { "PLASTIC_TMP" => @tmp, "CLAUDE_CODE_SESSION_ID" => session_id }
    Open3.capture3(env, "ruby", HOOK, @index, @home, "global", PLUGIN_ROOT, stdin_data: stdin_data)
  end

  def context(**kwargs)
    out, err, status = run_hook(**kwargs)
    assert_equal 0, status.exitstatus, err
    JSON.parse(out).dig("hookSpecificOutput", "additionalContext")
  end

  def write_node(dir, node)
    File.write(File.join(dir, "nodes", "#{node}.md"), <<~MD)
      ---
      node: #{node}
      kind: work
      files: []
      budget: 100000
      ---
      # #{node} - a node

      ## #{node} failure-mode matrix
      #{MATRIX}
      ## Steps
      1. do it

      ## Proven by
      (filled at close)
    MD
  end

  def write_graph(dir, graph_body)
    File.write(File.join(dir, "graph.md"), <<~MD)
      # Graph: Demo

      ## Goal
      Ship it.

      ## Decisions
      - D1 pick approach

      ## Graph
      #{graph_body}
      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD
  end

  # A single-node, parked delivery: n1 is needs_decision, so nothing is
  # ready and nothing is running - the plain "stalled" shape.
  def stalled_intent(id)
    dir = File.join(@store, "#{id}--stalled-demo")
    FileUtils.mkdir_p(File.join(dir, "nodes"))
    File.write(File.join(dir, "#{id}--stalled-demo.md"), "---\nid: \"#{id}\"\nintent: t\n---\n\n## Intent\nbody\n")
    write_graph(dir, "- n1 needs nothing\n")
    write_node(dir, "n1")
    File.write(File.join(dir, "savepoint.md"), "2026-09-13T00:00:00Z  n1  needs_decision question=q\n")
    File.write(File.join(dir, "delivery.lock"), "stale\n")
    dir
  end

  # A single-node delivery whose one node is done, with no Done line - the
  # plain "done_unreported" shape.
  def done_unreported_intent(id)
    dir = File.join(@store, "#{id}--done-demo")
    FileUtils.mkdir_p(File.join(dir, "nodes"))
    File.write(File.join(dir, "#{id}--done-demo.md"), "---\nid: \"#{id}\"\nintent: t\n---\n\n## Intent\nbody\n")
    write_graph(dir, "- n1 needs nothing\n")
    write_node(dir, "n1")
    File.write(File.join(dir, "savepoint.md"),
               "2026-09-13T00:00:00Z  n1  done holder=h gates=g1+g2 " \
               "commit=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa suite=1/1/0/0\n")
    File.write(File.join(dir, "delivery.lock"), "stale\n")
    dir
  end

  # A single-node delivery with nothing done and nothing parked: n1 is
  # ready, so the tick reports "moving" - a delivery that needs no
  # attention at all.
  def moving_intent(id)
    dir = File.join(@store, "#{id}--moving-demo")
    FileUtils.mkdir_p(File.join(dir, "nodes"))
    File.write(File.join(dir, "#{id}--moving-demo.md"), "---\nid: \"#{id}\"\nintent: t\n---\n\n## Intent\nbody\n")
    write_graph(dir, "- n1 needs nothing\n")
    write_node(dir, "n1")
    File.write(File.join(dir, "delivery.lock"), "stale\n")
    dir
  end

  # A directory whose savepoint.md is a directory, not a file: RunnerWatch's
  # own read (File.read, unguarded at that call site) raises partway through
  # the tick, proving the whole watch block is one guarded unit.
  def malformed_intent(id)
    dir = File.join(@store, "#{id}--broken-demo")
    FileUtils.mkdir_p(File.join(dir, "nodes"))
    File.write(File.join(dir, "#{id}--broken-demo.md"), "---\nid: \"#{id}\"\nintent: t\n---\n\n## Intent\nbody\n")
    write_graph(dir, "- n1 needs nothing\n")
    write_node(dir, "n1")
    FileUtils.mkdir_p(File.join(dir, "savepoint.md"))
    File.write(File.join(dir, "delivery.lock"), "stale\n")
    dir
  end

  def watch_state_path(dir)
    File.join(dir, "watch.state")
  end

  def watch_record_path(dir)
    File.join(dir, "watch.record")
  end

  # Row 3.7
  def test_watch_line_names_stalled_and_done_unreported_intents
    stalled_intent("911")
    done_unreported_intent("912")

    ctx = context
    line = ctx.lines.find { |l| l.include?("PLASTIC watch:") }
    assert line, "boot must carry one PLASTIC watch line naming both deliveries"
    assert_includes line, "911 stalled ("
    assert_includes line, "912 done_unreported"
  end

  # Row 3.8
  def test_watch_line_absent_when_nothing_needs_attention
    moving_intent("913")

    refute_includes context, "PLASTIC watch:"
  end

  # Row 3.9
  def test_boot_watch_leaves_snapshots_untouched
    dir = stalled_intent("914")

    context

    refute File.exist?(watch_state_path(dir)), "an unrecorded boot tick must never write watch.state"
    refute File.exist?(watch_record_path(dir)), "an unrecorded boot tick must never write watch.record"
  end

  # Row 3.10
  def test_subagent_boot_runs_no_watch
    dir = stalled_intent("915")
    payload = JSON.generate("session_id" => "sub-915", "agent_id" => "agent-1")

    ctx = context(stdin_data: payload, session_id: "sess-sub-915")

    refute_includes ctx, "PLASTIC watch:", "a subagent boot must never pay for a store walk"
    refute File.exist?(watch_state_path(dir))
    refute File.exist?(watch_record_path(dir))
  end

  # Row 3.11
  def test_watch_failure_never_blocks_boot
    malformed_intent("916")
    stalled_intent("917")

    out, err, status = run_hook
    assert_equal 0, status.exitstatus, err
    parsed = JSON.parse(out)
    assert_includes parsed["systemMessage"], "Plastic Core loaded",
                     "a raise inside one delivery's tick must still let boot finish"
    ctx = parsed.dig("hookSpecificOutput", "additionalContext")
    refute_includes ctx, "PLASTIC watch:",
                     "the whole watch block is one guarded unit; a raise on any candidate must add nothing"
  end
end
