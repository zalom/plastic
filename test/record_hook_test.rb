require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require_relative "../scripts/lib/session_ledger"
require_relative "../scripts/lib/lock"

# Intent 298: hook-record replaces hook-gate-check. It keeps the decoupled
# savepoint ledger (intent 34/52) byte for byte, promotes the session's newest
# pending day-ledger line when a project file lands (intent 297), calls the
# scripts/session-commit seam (intent 300) when present, and never blocks.
class RecordHookTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/hook-record", __dir__)
  SEAM_PATH = File.expand_path("../scripts/session-commit", __dir__)

  def setup
    @root = Dir.mktmpdir("record-hook")
    @home = Dir.mktmpdir("record-hook-home")
    @plastic_home = File.join(@home, ".plastic")
    @store = File.join(@plastic_home, "store")
    FileUtils.mkdir_p(@store)
    @intent_dir = File.join(@store, "52--x")
    FileUtils.mkdir_p(@intent_dir)
    @bridge_tmp = Dir.mktmpdir("record-hook-tmp")
    @saved_session = ENV["CLAUDE_CODE_SESSION_ID"]
    @saved_plastic_tmp = ENV["PLASTIC_TMP"]
    ENV.delete("CLAUDE_CODE_SESSION_ID")
    ENV["PLASTIC_TMP"] = @bridge_tmp
    # scripts/session-commit is intent 300's sibling file. Snapshot whatever is
    # there (nothing, today) before any test stubs it, so teardown restores the
    # real repo state exactly rather than assuming the file never existed.
    @seam_existed = File.exist?(SEAM_PATH)
    @seam_original = @seam_existed ? File.binread(SEAM_PATH) : nil
    @seam_original_mode = @seam_existed ? File.stat(SEAM_PATH).mode : nil
  end

  def teardown
    FileUtils.rm_rf(@root)
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@bridge_tmp)
    restore_env("CLAUDE_CODE_SESSION_ID", @saved_session)
    restore_env("PLASTIC_TMP", @saved_plastic_tmp)
    if @seam_existed
      File.binwrite(SEAM_PATH, @seam_original)
      File.chmod(@seam_original_mode, SEAM_PATH)
    else
      FileUtils.rm_f(SEAM_PATH)
    end
  end

  def restore_env(key, saved)
    saved.nil? ? ENV.delete(key) : ENV[key] = saved
  end

  def run_hook(file_path, session: nil, cwd: nil)
    payload = { "session_id" => session, "tool_input" => { "file_path" => file_path },
                "cwd" => cwd || @root }
    env = { "CLAUDE_CODE_SESSION_ID" => session, "PLASTIC_TMP" => @bridge_tmp, "PLASTIC_HOME" => @plastic_home,
            "HOME" => @home }
    out, status = Open3.capture2(env, "ruby", SCRIPT, stdin_data: JSON.generate(payload))
    [out, status]
  end

  def checklist_path(day = SessionLedger.day_id)
    SessionLedger.checklist_path(@store, day)
  end

  def savepoint_path(day = SessionLedger.day_id)
    SessionLedger.savepoint_path(@store, day)
  end

  # Tags the line with the SAME short session id hook-record derives internally
  # (SessionLedger.short_session_id(nil, session)), so set_state's session match
  # actually lines up: a raw "sess-1" written verbatim here would never equal
  # hook-record's own short-form "sess1" tag.
  def seed_pending_line(session, summary, day: SessionLedger.day_id, project: "plastic")
    FileUtils.mkdir_p(File.dirname(checklist_path(day)))
    line = SessionLedger.checklist_line(:pending, sid_for(session), project, summary)
    SessionLedger.append_line(checklist_path(day), line, header: SessionLedger.checklist_header(day))
  end

  def sid_for(session)
    SessionLedger.short_session_id(nil, session)
  end

  # --- 2.7 (344 n2): a delegate of a live delivery lock -------------------------

  # While a session is a delegate of a live delivery lock the day ledger goes
  # quiet: no pending line is promoted and no Item savepoint line lands. The
  # lock and session heartbeats still run.
  def test_record_skips_day_ledger_for_a_delegate_session
    seed_pending_line("sess-delegate", "do the thing")
    Lock.acquire(@intent_dir, session: "owner-session", run_mode: "auto")
    Lock.add_delegate(@intent_dir, delegate: "sess-delegate", session: "owner-session")
    sid = sid_for("sess-delegate")
    SessionLedger.ensure_tmp_root(@store)
    FileUtils.mkdir_p(SessionLedger.session_tmp_dir(@store, sid))
    before = File.read(checklist_path)

    _out, status = run_hook(File.join(@root, "app.rb"), session: "sess-delegate")
    assert_equal 0, status.exitstatus
    assert_equal before, File.read(checklist_path), "no pending line is promoted for a delivering delegate"
    refute File.exist?(savepoint_path), "no Item line lands in the day ledger"
    assert File.exist?(SessionLedger.heartbeat_path(@store, sid)), "the session heartbeat still runs"
  end

  # --- 2.8 (344 n2): no delivery lock at all still promotes ---------------------

  def test_record_promotes_pending_line_without_a_delivery_lock
    seed_pending_line("sess-1", "Promoted without a lock")
    project_file = File.join(@root, "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(project_file))
    File.write(project_file, "puts 1\n")

    out, status = run_hook(project_file, session: "sess-1", cwd: @root)
    assert_equal 0, status.exitstatus, out

    parsed = File.read(checklist_path).lines.map { |l| SessionLedger.parse_checklist_line(l) }.compact
    line = parsed.find { |l| l[:summary] == "Promoted without a lock" }
    assert_equal :open, line[:state], "no delivery lock means promotion still runs"
  end

  # --- malformed stdin, no file_path -----------------------------------------

  def test_malformed_stdin_exits_zero_nothing_written
    env = { "PLASTIC_TMP" => @bridge_tmp, "PLASTIC_HOME" => @plastic_home, "HOME" => @home,
            "CLAUDE_CODE_SESSION_ID" => nil }
    out, status = Open3.capture2(env, "ruby", SCRIPT, stdin_data: "not valid json{{{")
    assert_equal 0, status.exitstatus
    assert_empty out.strip
    refute File.exist?(SessionLedger.sessions_root(@store))
  end

  def test_no_file_path_exits_zero_nothing_written
    payload = { "session_id" => "abc" }
    env = { "PLASTIC_TMP" => @bridge_tmp, "PLASTIC_HOME" => @plastic_home, "HOME" => @home,
            "CLAUDE_CODE_SESSION_ID" => nil }
    out, status = Open3.capture2(env, "ruby", SCRIPT, stdin_data: JSON.generate(payload))
    assert_equal 0, status.exitstatus
    assert_empty out.strip
    refute File.exist?(SessionLedger.sessions_root(@store))
  end

  # --- decoupled savepoint (moved from gate_check_test.rb) --------------------

  def test_savepoint_written_without_bridge_or_session
    intent_file = File.join(@intent_dir, "52--x.md")
    File.write(intent_file, "## Intent\nx\n")
    spec = File.join(@intent_dir, "spec.md")
    File.write(spec, "spec\n")

    out, status = run_hook(spec)

    assert_equal 0, status.exitstatus, "hook should exit 0, got: #{out}"
    ledger = File.join(@intent_dir, "savepoint.md")
    assert File.exist?(ledger), "savepoint.md must be created"
    assert_includes File.read(ledger), "spec.md created"
  end

  def test_savepoint_idempotent_across_runs
    File.write(File.join(@intent_dir, "52--x.md"), "## Intent\nx\n")
    spec = File.join(@intent_dir, "spec.md")
    File.write(spec, "spec\n")

    run_hook(spec)
    run_hook(spec)
    ledger = File.read(File.join(@intent_dir, "savepoint.md"))
    assert_equal 1, ledger.lines.count { |l| l.include?("spec.md created") }
  end

  def test_checklist_landing_emits_exec_started
    File.write(File.join(@intent_dir, "52--x.md"), "## Intent\nx\n")
    checklist = File.join(@intent_dir, "checklist.md")
    File.write(checklist, "# Checklist\nreal\n")

    out, status = run_hook(checklist)
    assert_equal 0, status.exitstatus, "hook should exit 0, got: #{out}"

    ledger = File.read(File.join(@intent_dir, "savepoint.md"))
    assert_includes ledger, "checklist.md created"
    assert_includes ledger, "Exec  started", "checklist landing must emit the Exec-started companion"
  end

  def test_exec_started_not_emitted_for_placeholder_checklist
    File.write(File.join(@intent_dir, "52--x.md"), "## Intent\nx\n")
    checklist = File.join(@intent_dir, "checklist.md")
    File.write(checklist, "<!-- plastic:placeholder -->\n\nplaceholder\n")

    run_hook(checklist)
    ledger_path = File.join(@intent_dir, "savepoint.md")
    ledger = File.exist?(ledger_path) ? File.read(ledger_path) : ""
    refute_includes ledger, "Exec  started", "a sentinel checklist must not emit Exec started"
  end

  # --- (b) inside an intent dir: savepoint only, no day-ledger write ----------

  def test_file_inside_intent_dir_appends_savepoint_no_day_ledger_write
    File.write(File.join(@intent_dir, "52--x.md"), "## Intent\nx\n")
    resource = File.join(@intent_dir, "resources", "note.md")
    FileUtils.mkdir_p(File.dirname(resource))
    File.write(resource, "note")

    out, status = run_hook(resource, session: "sess-1")
    assert_equal 0, status.exitstatus, out
    refute File.exist?(checklist_path), "a write inside an intent dir must not touch the day ledger"
  end

  # --- (b) inside ~/.plastic but not an intent dir: nothing but heartbeat -----

  # 344 n2 (D4-D5): the heartbeat guard now checks the session tmp directory
  # directly rather than the retired pointer, so this fixture creates the
  # directory first, exactly like a real booted session, before asserting the
  # heartbeat lands.
  def test_file_inside_plastic_home_not_an_intent_dir_writes_only_heartbeat
    plain = File.join(@plastic_home, "PLASTIC.md")
    File.write(plain, "conventions")
    sid = SessionLedger.short_session_id(nil, "sess-1")
    FileUtils.mkdir_p(SessionLedger.session_tmp_dir(@store, sid))
    heartbeat = SessionLedger.heartbeat_path(@store, sid)

    out, status = run_hook(plain, session: "sess-1")
    assert_equal 0, status.exitstatus, out
    assert File.exist?(heartbeat), "heartbeat must still be written when the session tmp dir exists"
    refute File.exist?(checklist_path), "no day-ledger write for a plain ~/.plastic file"
    refute File.exist?(File.join(@intent_dir, "savepoint.md")), "no savepoint for a non-intent-dir file"
  end

  # --- 2.9 (344 n2): no session tmp dir at all means no directory is created ---

  def test_record_creates_no_tmp_dir_for_an_unstarted_session
    plain = File.join(@plastic_home, "PLASTIC.md")
    File.write(plain, "conventions")
    sid = SessionLedger.short_session_id(nil, "sess-orphan")
    refute File.exist?(SessionLedger.session_tmp_dir(@store, sid)), "fixture must start with no tmp dir"

    out, status = run_hook(plain, session: "sess-orphan")
    assert_equal 0, status.exitstatus, out
    refute File.exist?(SessionLedger.session_tmp_dir(@store, sid)),
           "an unstarted session must not gain a .tmp/<sid>/ directory from record"
  end

  # --- (c) project file, pending line exists -----------------------------------

  def test_project_file_pending_line_exists_promotes_and_appends_item_and_calls_seam
    seed_pending_line("sess-1", "About the widget page")
    seam_calls = File.join(@root, "seam-calls.log")
    File.write(SEAM_PATH, <<~SH)
      #!/bin/bash
      echo "$@" >> #{seam_calls}
      exit 0
    SH
    FileUtils.chmod(0o755, SEAM_PATH)

    project_file = File.join(@root, "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(project_file))
    File.write(project_file, "puts 1\n")

    out, status = run_hook(project_file, session: "sess-1", cwd: @root)
    assert_equal 0, status.exitstatus, out

    parsed = File.read(checklist_path).lines.map { |l| SessionLedger.parse_checklist_line(l) }.compact
    line = parsed.find { |l| l[:summary] == "About the widget page" }
    assert_equal :open, line[:state], "the pending line must flip to open"

    ledger = File.read(savepoint_path)
    assert_includes ledger, "About the widget page"
    assert_includes ledger, "Item"

    assert File.exist?(seam_calls), "the seam must have been called"
    call = File.read(seam_calls)
    assert_includes call, "About the widget page"
    assert_includes call, sid_for("sess-1")
  end

  # --- (c) project file, no pending line ---------------------------------------

  def test_project_file_no_pending_line_exits_zero_no_savepoint_no_seam
    seam_calls = File.join(@root, "seam-calls.log")
    File.write(SEAM_PATH, "#!/bin/bash\necho called >> #{seam_calls}\nexit 0\n")
    FileUtils.chmod(0o755, SEAM_PATH)

    project_file = File.join(@root, "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(project_file))
    File.write(project_file, "puts 1\n")

    out, status = run_hook(project_file, session: "sess-1", cwd: @root)
    assert_equal 0, status.exitstatus, out
    refute File.exist?(seam_calls), "the seam must not be called with no pending line"
    refute File.exist?(savepoint_path), "no Item savepoint line without a pending match"
  end

  # --- row A10: a rejected prompt disables the turn's auto-commit (spec D7) ---
  #
  # SessionLedger.set_state promotes only a checklist line matching the session
  # id, and hook-record spawns session-commit only on a promotion. A prompt
  # capture_worthy? rejects never gets a pending line in the first place, so
  # its turn gets no Item savepoint line and no session-commit spawn either --
  # intended (D7), not a bug, and pinned here end to end through the real
  # hook-capture script.

  def capture_script
    File.expand_path("../scripts/hook-capture", __dir__)
  end

  def run_capture(prompt, session:)
    payload = { "session_id" => session, "user_prompt" => prompt, "cwd" => @root }
    env = { "PLASTIC_HOME" => @plastic_home, "HOME" => @home, "CLAUDE_CODE_SESSION_ID" => nil }
    Open3.capture2(env, "ruby", capture_script, stdin_data: JSON.generate(payload))
  end

  def test_a10_rejected_prompt_yields_no_pending_line_no_item_no_seam_call
    run_capture("what does the arm verb do to the worktree?", session: "sess-rejected")
    refute File.exist?(checklist_path), "a rejected prompt must not scaffold a pending line"

    seam_calls = File.join(@root, "seam-calls.log")
    File.write(SEAM_PATH, "#!/bin/bash\necho called >> #{seam_calls}\nexit 0\n")
    FileUtils.chmod(0o755, SEAM_PATH)

    project_file = File.join(@root, "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(project_file))
    File.write(project_file, "puts 1\n")

    out, status = run_hook(project_file, session: "sess-rejected", cwd: @root)
    assert_equal 0, status.exitstatus, out
    refute File.exist?(seam_calls), "no session-commit for a turn whose prompt was rejected"
    refute File.exist?(savepoint_path), "no Item savepoint line for a rejected prompt's turn"
  end

  def test_a10_accepted_prompt_yields_a_pending_line_an_item_and_a_seam_call
    run_capture("fix the dashboard date parser for the wikilink form", session: "sess-accepted")
    lines = File.read(checklist_path).lines.map { |l| SessionLedger.parse_checklist_line(l) }.compact
    assert(lines.any? { |l| l[:session] == sid_for("sess-accepted") && l[:state] == :pending },
           "an accepted prompt must scaffold a pending line")

    seam_calls = File.join(@root, "seam-calls.log")
    File.write(SEAM_PATH, "#!/bin/bash\necho called >> #{seam_calls}\nexit 0\n")
    FileUtils.chmod(0o755, SEAM_PATH)

    project_file = File.join(@root, "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(project_file))
    File.write(project_file, "puts 1\n")

    out, status = run_hook(project_file, session: "sess-accepted", cwd: @root)
    assert_equal 0, status.exitstatus, out
    assert File.exist?(seam_calls), "the seam must be called for a turn whose prompt was accepted"
    assert File.exist?(savepoint_path), "an Item savepoint line must land for an accepted prompt's turn"
  end

  # --- seam missing, hangs, or exits 1: exit 0 in every case -------------------

  def test_seam_script_missing_exits_zero
    FileUtils.rm_f(SEAM_PATH)
    seed_pending_line("sess-1", "Missing seam item")
    project_file = File.join(@root, "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(project_file))
    File.write(project_file, "puts 1\n")

    out, status = run_hook(project_file, session: "sess-1", cwd: @root)
    assert_equal 0, status.exitstatus, out
  end

  def test_seam_script_exits_nonzero_still_exits_zero
    File.write(SEAM_PATH, "#!/bin/bash\nexit 1\n")
    FileUtils.chmod(0o755, SEAM_PATH)
    seed_pending_line("sess-1", "Failing seam item")
    project_file = File.join(@root, "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(project_file))
    File.write(project_file, "puts 1\n")

    out, status = run_hook(project_file, session: "sess-1", cwd: @root)
    assert_equal 0, status.exitstatus, out
  end

  def test_seam_script_hangs_past_ten_seconds_still_exits_zero
    File.write(SEAM_PATH, "#!/bin/bash\nsleep 30\nexit 0\n")
    FileUtils.chmod(0o755, SEAM_PATH)
    seed_pending_line("sess-1", "Hanging seam item")
    project_file = File.join(@root, "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(project_file))
    File.write(project_file, "puts 1\n")

    started = Time.now
    out, status = run_hook(project_file, session: "sess-1", cwd: @root)
    elapsed = Time.now - started
    assert_equal 0, status.exitstatus, out
    assert_operator elapsed, :<, 15, "the seam must be bounded by its own 10s timeout"
  end

  # --- a condition that used to make gate-check exit 2 (pre-How auto edit) ----

  def test_condition_that_used_to_gate_now_exits_zero_with_no_decision_key
    File.write(File.join(@intent_dir, "52--x.md"), "## Intent\nx\n")
    plan = File.join(@intent_dir, "plan.md") # plan.md with no spec.md present
    File.write(plan, "# Plan\n")

    out, status = run_hook(plan, session: "sess-1")
    assert_equal 0, status.exitstatus, out
    refute_includes out, "decision"
  end

  # --- two records race on one pending line: exactly one flip (297 atomicity) --

  def test_two_concurrent_records_flip_exactly_one_pending_line
    seed_pending_line("sess-1", "Race target item")
    project_file = File.join(@root, "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(project_file))
    File.write(project_file, "puts 1\n")

    results = []
    threads = 2.times.map do
      Thread.new { results << run_hook(project_file, session: "sess-1", cwd: @root) }
    end
    threads.each(&:join)

    results.each { |out, status| assert_equal 0, status.exitstatus, out }

    parsed = File.read(checklist_path).lines.map { |l| SessionLedger.parse_checklist_line(l) }.compact
    flipped = parsed.select { |l| l[:summary] == "Race target item" && l[:state] == :open }
    assert_equal 1, flipped.length, "exactly one racer must flip the line"

    savepoint_lines = File.exist?(savepoint_path) ? File.read(savepoint_path).lines : []
    item_lines = savepoint_lines.select { |l| l.include?("Race target item") && l.include?("Item") }
    assert_equal 1, item_lines.length, "exactly one Item savepoint line for the one flip"
  end
end
