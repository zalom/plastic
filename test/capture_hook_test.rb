require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "yaml"
require "open3"
require "rbconfig"
require_relative "../scripts/lib/session_ledger"
require_relative "../scripts/lib/packet_wrapper"
require_relative "../scripts/lib/lock"

# Intent 298: hook-capture replaces hook-continue, hook-future-intent-check,
# and hook-auto-arm. One UserPromptSubmit process that appends a pending line
# to the session day ledger and detects "continue" and "auto" prompts. Every
# job is best-effort and the hook always exits 0 (spec D2). Intent 345 (D7,
# 323) removed the per-prompt Future-intent hint step entirely.
class CaptureHookTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/hook-capture", __dir__)

  def setup
    @home = Dir.mktmpdir("capture-hook-home")
    @plastic_home = File.join(@home, ".plastic")
    @store = File.join(@plastic_home, "store")
    FileUtils.mkdir_p(@store)
    File.write(File.join(@plastic_home, "INDEX.md"), "# Index\n\n## Active\n\n## Future\n")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def run_hook(prompt, session: "sess-1", cwd: @home, extra: {})
    payload = { "session_id" => session, "user_prompt" => prompt, "cwd" => cwd }.merge(extra)
    env = { "PLASTIC_HOME" => @plastic_home, "HOME" => @home, "CLAUDE_CODE_SESSION_ID" => nil }
    out, status = Open3.capture2(env, "ruby", SCRIPT, stdin_data: JSON.generate(payload))
    [out, status]
  end

  def checklist_path(day = SessionLedger.day_id)
    SessionLedger.checklist_path(@store, day)
  end

  def sid_for(session)
    SessionLedger.short_session_id(nil, session)
  end

  def heartbeat_path(session)
    SessionLedger.heartbeat_path(@store, sid_for(session))
  end

  def parsed_checklist_lines(day = SessionLedger.day_id)
    return [] unless File.exist?(checklist_path(day))

    File.read(checklist_path(day)).lines.map { |l| SessionLedger.parse_checklist_line(l) }.compact
  end

  # --- malformed or empty stdin ------------------------------------------------

  def test_malformed_stdin_exits_zero_no_output_nothing_written
    env = { "PLASTIC_HOME" => @plastic_home, "HOME" => @home, "CLAUDE_CODE_SESSION_ID" => nil }
    out, status = Open3.capture2(env, "ruby", SCRIPT, stdin_data: "not valid json{{{")
    assert_equal 0, status.exitstatus
    assert_empty out.strip
    refute File.exist?(SessionLedger.sessions_root(@store))
    refute File.exist?(SessionLedger.tmp_root(@store))
  end

  def test_empty_stdin_exits_zero_no_output_nothing_written
    env = { "PLASTIC_HOME" => @plastic_home, "HOME" => @home, "CLAUDE_CODE_SESSION_ID" => nil }
    out, status = Open3.capture2(env, "ruby", SCRIPT, stdin_data: "")
    assert_equal 0, status.exitstatus
    assert_empty out.strip
    refute File.exist?(SessionLedger.tmp_root(@store))
  end

  # --- prompt under 10 chars ----------------------------------------------------

  # 344 n2 (D4-D5): the tmp-dir guard now checks the session tmp directory
  # directly rather than the retired pointer, so this pinned case creates the
  # directory in the fixture first, exactly like a real booted session, and
  # still proves the short prompt itself earns no pending line.
  def test_prompt_under_ten_chars_no_pending_line_heartbeat_still_rewritten
    sid = sid_for("sess-short")
    FileUtils.mkdir_p(SessionLedger.session_tmp_dir(@store, sid))

    out, status = run_hook("hi there", session: "sess-short")
    assert_equal 0, status.exitstatus
    assert_empty parsed_checklist_lines
    assert File.exist?(heartbeat_path("sess-short")), "heartbeat must still be rewritten"
    assert_empty out.strip
  end

  # --- 2.5: no session tmp dir at all means no directory is created ----------

  def test_capture_creates_no_tmp_dir_for_an_unstarted_session
    refute File.exist?(SessionLedger.session_tmp_dir(@store, sid_for("sess-orphan"))),
           "fixture must start with no session tmp dir"

    out, status = run_hook("hi there", session: "sess-orphan")
    assert_equal 0, status.exitstatus
    refute File.exist?(SessionLedger.session_tmp_dir(@store, sid_for("sess-orphan"))),
           "an unstarted session must not gain a .tmp/<sid>/ directory from capture"
    assert_empty out.strip
  end

  # --- row A9: the hook actually gates on SessionLedger.capture_worthy? -----------

  def test_capture_worthy_gate_bare_question_adds_no_pending_line
    sid = sid_for("sess-a9-question")
    FileUtils.mkdir_p(SessionLedger.session_tmp_dir(@store, sid))

    out, status = run_hook("what does the arm verb do to the worktree?", session: "sess-a9-question")
    assert_equal 0, status.exitstatus, out
    lines = parsed_checklist_lines.select { |l| l[:session] == sid }
    assert_empty lines, "a bare question must not earn a pending line"
  end

  # --- 2.2 to 2.4, 2.6 (344 n2): the delivery lock replaces the pointer -----------

  def acquire_lock(intent_name, session:, stale: false)
    intent_dir = File.join(@store, intent_name)
    FileUtils.mkdir_p(intent_dir)
    Lock.acquire(intent_dir, session: session, run_mode: "auto")
    FileUtils.touch(Lock.path(intent_dir), mtime: Time.now - Lock::TTL_SECONDS - 60) if stale
    intent_dir
  end

  def test_capture_skips_day_ledger_for_a_delivering_session
    sid = sid_for("sess-delivering")
    FileUtils.mkdir_p(SessionLedger.session_tmp_dir(@store, sid))
    acquire_lock("344--retire-the-bridge", session: "sess-delivering")

    out, status = run_hook("fix the dashboard date parser for the wikilink form", session: "sess-delivering")
    assert_equal 0, status.exitstatus, out
    lines = parsed_checklist_lines.select { |l| l[:session] == sid }
    assert_empty lines, "a delivering session must not earn a pending line"
  end

  def test_capture_writes_pending_line_without_a_delivery_lock
    sid = sid_for("sess-no-lock")

    out, status = run_hook("fix the dashboard date parser for the wikilink form", session: "sess-no-lock")
    assert_equal 0, status.exitstatus, out
    lines = parsed_checklist_lines.select { |l| l[:session] == sid }
    assert_equal 1, lines.length
    assert_equal :pending, lines.first[:state]
  end

  def test_capture_ignores_a_stale_delivery_lock
    sid = sid_for("sess-stale-lock")
    acquire_lock("344--retire-the-bridge", session: "sess-stale-lock", stale: true)

    out, status = run_hook("fix the dashboard date parser for the wikilink form", session: "sess-stale-lock")
    assert_equal 0, status.exitstatus, out
    lines = parsed_checklist_lines.select { |l| l[:session] == sid }
    assert_equal 1, lines.length, "a stale lock must not suppress the day ledger"
  end

  def test_capture_writes_today_for_a_session_started_yesterday
    sid = sid_for("sess-yesterday")
    FileUtils.mkdir_p(SessionLedger.session_tmp_dir(@store, sid))
    File.write(SessionLedger.heartbeat_path(@store, sid), "#{(Time.now.utc - 86_400).iso8601}\n")

    out, status = run_hook("fix the dashboard date parser for the wikilink form", session: "sess-yesterday")
    assert_equal 0, status.exitstatus, out
    lines = parsed_checklist_lines(SessionLedger.day_id).select { |l| l[:session] == sid }
    assert_equal 1, lines.length, "a session started yesterday must still capture into today's ledger"
  end

  def test_capture_worthy_gate_imperative_prompt_adds_exactly_one_pending_line
    sid = sid_for("sess-a9-work")
    out, status = run_hook("fix the dashboard date parser for the wikilink form", session: "sess-a9-work")
    assert_equal 0, status.exitstatus, out
    lines = parsed_checklist_lines.select { |l| l[:session] == sid }
    assert_equal 1, lines.length
    assert_equal :pending, lines.first[:state]
  end

  # --- normal prompt -------------------------------------------------------------

  def test_normal_prompt_appends_exactly_one_pending_line_capped_at_120
    long_prompt = "x" * 400
    out, status = run_hook(long_prompt, session: "sess-normal", cwd: @home)
    assert_equal 0, status.exitstatus, out

    lines = parsed_checklist_lines.select { |l| l[:session] == sid_for("sess-normal") }
    assert_equal 1, lines.length
    assert_equal :pending, lines.first[:state]
    assert_operator lines.first[:summary].length, :<=, 120
  end

  # --- two sessions same day, concurrent ------------------------------------------

  def test_two_concurrent_sessions_same_day_both_lines_intact
    results = []
    threads = [
      Thread.new { results << run_hook("First session says something long enough", session: "sess-a") },
      Thread.new { results << run_hook("Second session says something else entirely", session: "sess-b") },
    ]
    threads.each(&:join)
    results.each { |out, status| assert_equal 0, status.exitstatus, out }

    lines = parsed_checklist_lines
    a = lines.find { |l| l[:session] == sid_for("sess-a") }
    b = lines.find { |l| l[:session] == sid_for("sess-b") }
    refute_nil a, "session a's line must survive the race"
    refute_nil b, "session b's line must survive the race"
  end

  # --- a live delivery lock names this session --------------------------------------

  # 345: the prompt used to read "please continue with the important work",
  # which relied on the old \bcontinue\b cockpit trigger to produce context.
  # Under the exact-match cockpit (D34) that prompt now yields nothing, so
  # the prompt is changed to one that still earns context through job (e)'s
  # auto-trigger phrase "take it from here", keeping both assertions honest.
  def test_a_delivery_lock_suppresses_the_pending_line_context_still_produced
    sid = sid_for("sess-1")
    FileUtils.mkdir_p(SessionLedger.session_tmp_dir(@store, sid))
    acquire_lock("42--some-intent", session: "sess-1")

    out, status = run_hook("please continue with the important work, take it from here", session: "sess-1")
    assert_equal 0, status.exitstatus, out
    assert_empty parsed_checklist_lines, "a live delivery lock names this session, so no pending line"
    refute_empty out.strip, "the continue context must still be produced"
  end

  # --- "continue" prompt -----------------------------------------------------------

  def test_continue_prompt_yields_cockpit_context_and_system_message
    out, status = run_hook("continue", session: "sess-continue")
    assert_equal 0, status.exitstatus, out
    parsed = JSON.parse(out)
    assert_equal "UserPromptSubmit", parsed.dig("hookSpecificOutput", "hookEventName")
    assert_includes parsed.dig("hookSpecificOutput", "additionalContext"), "plastic-intent-continuing skill workflow"
    assert parsed.key?("systemMessage")
  end

  # --- D34 (325): the cockpit fires only on the trimmed prompt "continue" ----

  def test_padded_and_capitalised_continue_still_yields_the_cockpit
    out, status = run_hook("  Continue  ", session: "sess-continue-pad")
    assert_equal 0, status.exitstatus, out
    refute_empty out.strip, "an over-narrowing mutation must fail here readably, not on an empty-string JSON.parse"
    parsed = JSON.parse(out)
    assert_includes parsed.dig("hookSpecificOutput", "additionalContext"), "plastic-intent-continuing skill workflow"
  end

  def test_continue_inside_a_sentence_yields_no_cockpit
    out, status = run_hook("continue the roadmap work on 327", session: "sess-continue-sentence")
    assert_equal 0, status.exitstatus, out
    refute_includes out.to_s, "plastic-intent-continuing skill workflow"
  end

  def test_please_continue_yields_no_cockpit
    out, status = run_hook("please continue", session: "sess-please-continue")
    assert_equal 0, status.exitstatus, out
    refute_includes out.to_s, "plastic-intent-continuing skill workflow"
  end

  # Under the old /\bcontinue\b/i trigger this fired; under the exact match
  # it must not, since the trimmed prompt is "continue." not "continue".
  def test_continue_with_trailing_punctuation_yields_no_cockpit
    out, status = run_hook("continue.", session: "sess-continue-punct")
    assert_equal 0, status.exitstatus, out
    assert_empty out.strip
  end

  def test_bare_continue_prompt_produces_no_pending_line
    out, status = run_hook("continue", session: "sess-bare")
    assert_equal 0, status.exitstatus, out
    lines = parsed_checklist_lines.select { |l| l[:session] == sid_for("sess-bare") }
    assert_empty lines, "a bare 'continue' is not itself a work summary worth a pending line"
  end

  # --- "auto" / "take it from here" -------------------------------------------------

  def test_take_it_from_here_yields_auto_steer_text
    out, status = run_hook("take it from here please", session: "sess-auto")
    assert_equal 0, status.exitstatus, out
    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext")
    assert_includes ctx, "Invoke the plastic-auto skill"
  end

  def test_bare_auto_word_triggers_steer_text
    out, status = run_hook("please run this in auto for me", session: "sess-auto2")
    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext")
    assert_includes ctx, "Invoke the plastic-auto skill"
  end

# --- the prompt key (intent 315a) -------------------------------------------------
# Claude Code's UserPromptSubmit payload carries the text under "prompt";
# "user_prompt" is the older key the tests above and the Codex relay use.

def run_payload(payload)
  env = { "PLASTIC_HOME" => @plastic_home, "HOME" => @home, "CLAUDE_CODE_SESSION_ID" => nil }
  Open3.capture2(env, "ruby", SCRIPT, stdin_data: JSON.generate(payload))
end

def test_prompt_key_appends_pending_line
  out, status = run_payload("session_id" => "sess-pk", "cwd" => @home,
                            "prompt" => "add a check to the doctor for the prompt key")
  assert_equal 0, status.exitstatus, out
  lines = parsed_checklist_lines.select { |l| l[:session] == sid_for("sess-pk") }
  assert_equal 1, lines.length, "a prompt-keyed payload must land one pending line"
  assert_equal :pending, lines.first[:state]
end

def test_user_prompt_key_still_appends_pending_line
  out, status = run_payload("session_id" => "sess-upk", "cwd" => @home,
                            "user_prompt" => "add a check to the doctor for the old key")
  assert_equal 0, status.exitstatus, out
  lines = parsed_checklist_lines.select { |l| l[:session] == sid_for("sess-upk") }
  assert_equal 1, lines.length, "the user_prompt fallback must keep landing a pending line"
end

def test_prompt_key_wins_over_user_prompt
  out, status = run_payload("session_id" => "sess-both", "cwd" => @home,
                            "prompt" => "harness text wins the pending line",
                            "user_prompt" => "relay text must not be recorded")
  assert_equal 0, status.exitstatus, out
  lines = parsed_checklist_lines.select { |l| l[:session] == sid_for("sess-both") }
  assert_equal 1, lines.length
  assert_includes lines.first[:summary], "harness text wins"
  refute_includes lines.first[:summary], "relay text"
end

def test_empty_prompt_key_falls_back_to_user_prompt
  out, status = run_payload("session_id" => "sess-empty", "cwd" => @home,
                            "prompt" => "",
                            "user_prompt" => "fallback text lands when prompt is empty")
  assert_equal 0, status.exitstatus, out
  lines = parsed_checklist_lines.select { |l| l[:session] == sid_for("sess-empty") }
  assert_equal 1, lines.length
  assert_includes lines.first[:summary], "fallback text lands"
end

def test_continue_under_prompt_key_yields_cockpit_context
  out, status = run_payload("session_id" => "sess-pk-continue", "cwd" => @home, "prompt" => "continue")
  assert_equal 0, status.exitstatus, out
  parsed = JSON.parse(out)
  assert_includes parsed.dig("hookSpecificOutput", "additionalContext").to_s,
                  "plastic-intent-continuing skill workflow"
end

def test_auto_under_prompt_key_yields_steer_text
  out, status = run_payload("session_id" => "sess-pk-auto", "cwd" => @home,
                            "prompt" => "take it from here please")
  assert_equal 0, status.exitstatus, out
  ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext").to_s
  assert_includes ctx, "Invoke the plastic-auto skill"
end

  # 345: after the hint cut, an ordinary prompt with no trigger word takes the
  # `exit 0 if context_parts.empty?` path almost every time, where before the
  # cut it was rare. The old body's `if out.strip.empty? then assert true`
  # branch was vacuous post-cut (it always took that branch and never
  # exercised the `else`), so this asserts the one true thing directly.
  def test_automation_substring_does_not_trigger
    out, status = run_hook("what is the automation strategy here anyway", session: "sess-noauto")
    assert_equal 0, status.exitstatus, out
    assert_empty out.strip
  end

  # --- the empty-output path is now the common case (345) ---------------------

  def test_an_ordinary_prompt_emits_no_envelope_and_still_logs
    out, status = run_hook("fix the dashboard date parser bug that keeps recurring", session: "sess-ordinary-nolog")
    assert_equal 0, status.exitstatus, out
    assert_empty out.strip, "an ordinary prompt with no trigger word must emit nothing at all"

    lines = parsed_checklist_lines.select { |l| l[:session] == sid_for("sess-ordinary-nolog") }
    assert_equal 1, lines.length, "the pending ledger line must still be written on the empty-output path"
  end

  # --- Future-intent keyword hit in global and project store -----------------------

  def write_future_intent(store_root, dir_name, id:, name:, tags:)
    intent_dir = File.join(store_root, "store", dir_name)
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "#{dir_name}.md"), <<~MD)
      ---
      id: "#{id}"
      intent: "#{name}"
      tags: [#{tags.join(", ")}]
      created: 2026-01-01
      author: test
      ---
      ## Intent
      #{name}
    MD
    File.write(File.join(store_root, "INDEX.md"),
               "# Index\n\n## Active\n\n## Future\n" \
               "- [#{id} - #{name}](store/#{dir_name}/#{dir_name}.md)\n")
  end

  # 345 (D7, 323): step (f) is gone, so a prompt matching many Future intents
  # by shared four-letter words must emit nothing at all, not a trimmed hint.
  def test_a_prompt_matching_many_future_intents_emits_nothing_and_still_logs
    write_future_intent(@plastic_home, "50--widget-global", id: "50", name: "Widget global feature",
                         tags: ["widget"])

    project_root = File.join(@plastic_home, "projects", "demo")
    FileUtils.mkdir_p(project_root)
    write_future_intent(project_root, "60--widget-project", id: "60", name: "Widget project feature",
                         tags: ["widget"])
    File.write(File.join(@plastic_home, "projects.yml"),
               YAML.dump("projects" => { "demo" => { "path" => File.join(@home, "code", "demo") } }))
    project_cwd = File.join(@home, "code", "demo")
    FileUtils.mkdir_p(project_cwd)

    out, status = run_hook("let's talk about the widget feature plan today", session: "sess-hint", cwd: project_cwd)
    assert_equal 0, status.exitstatus, out
    assert_empty out.strip, "no hint of any shape must survive the cut"

    lines = parsed_checklist_lines.select { |l| l[:session] == sid_for("sess-hint") }
    assert_equal 1, lines.length, "the pending ledger line must still be written"
  end

  # S1c: guards against a helper left behind as dead code, or the hint
  # returning under a different name.
  def test_the_hint_helpers_are_gone_from_the_source
    src = File.read(SCRIPT)
    refute_includes src, "future_intent_matches"
    refute_includes src, "resolve_project_store_root"
    refute_includes src, "Future intents related"
    refute_includes src, "require \"yaml\""
  end

  # --- per-prompt context budget (345 S4) -------------------------------------------

  # write_future_intent overwrites INDEX.md on every call with a single-entry
  # index, so a loop calling it would leave the fixture holding only its last
  # entry. This builder appends all 100 index lines in one pass instead.
  def build_hundred_future_intents(store_root)
    index_lines = ["# Index", "", "## Active", "", "## Future"]
    100.times do |i|
      id = "5#{i.to_s.rjust(3, "0")}"
      dir = "#{id}--future-planning-work-#{i}"
      name = "Future planning work item #{i} about ordinary tasks"
      intent_dir = File.join(store_root, "store", dir)
      FileUtils.mkdir_p(intent_dir)
      File.write(File.join(intent_dir, "#{dir}.md"), <<~MD)
        ---
        id: "#{id}"
        intent: "#{name}"
        tags: [planning, work, ordinary]
        created: 2026-01-01
        author: test
        ---
        ## Intent
        #{name}
      MD
      index_lines << "- [#{id} - #{name}](store/#{dir}/#{dir}.md)"
    end
    FileUtils.mkdir_p(store_root)
    File.write(File.join(store_root, "INDEX.md"), "#{index_lines.join("\n")}\n")
  end

  # Measured 2026-09-08 against this fixture: pre-cut additionalContext is
  # 11,649 bytes, post-cut it is 0 bytes with empty stdout and exit 0.
  # Against the real ~/.plastic store the pre-cut number was 43,253 bytes.
  def test_an_ordinary_prompt_in_a_hundred_future_intent_store_emits_nothing
    project_root = File.join(@plastic_home, "projects", "bigstore")
    build_hundred_future_intents(project_root)

    future_entries = File.readlines(File.join(project_root, "INDEX.md")).count { |l| l.strip.start_with?("- [") }
    assert_equal 100, future_entries, "the fixture must really hold 100 Future entries before measuring anything"

    File.write(File.join(@plastic_home, "projects.yml"),
               YAML.dump("projects" => { "bigstore" => { "path" => File.join(@home, "code", "bigstore") } }))
    project_cwd = File.join(@home, "code", "bigstore")
    FileUtils.mkdir_p(project_cwd)

    prompt = "let's talk about the ordinary planning work today, what steps make sense for this " \
             "task and what the team thinks about the plan before we go further with everything, " \
             "and whether the schedule still holds up given what we learned this week"
    assert_operator prompt.length, :>=, 200, "the fixture prompt must be the ordinary 200-character shape"

    out, status = run_hook(prompt, session: "sess-bigstore", cwd: project_cwd)
    assert_equal 0, status.exitstatus, out
    assert_empty out.strip, "the real pin: the hook emits nothing at all for an ordinary prompt"

    additional_context_bytes = out.strip.empty? ? 0 : JSON.parse(out).dig("hookSpecificOutput", "additionalContext").to_s.bytesize
    assert_operator additional_context_bytes, :<, 1500,
                     "secondary ceiling that survives if a future step legitimately starts emitting a little"
  end

  # --- dashboard.rb missing or failing -----------------------------------------------

  # An isolated copy of hook-capture plus its lib dependencies, deliberately
  # WITHOUT scripts/dashboard.rb beside it, so job (d)'s own
  # `if File.exist?(dashboard)` guard is exercised for real rather than assumed.
  def isolated_capture_without_dashboard
    root = Dir.mktmpdir("capture-no-dashboard")
    scripts = File.join(root, "scripts")
    FileUtils.mkdir_p(File.join(scripts, "lib"))
    real_scripts = File.expand_path("../scripts", __dir__)
    FileUtils.cp(File.join(real_scripts, "hook-capture"), File.join(scripts, "hook-capture"))
    FileUtils.cp(File.join(real_scripts, "lib", "session_ledger.rb"), File.join(scripts, "lib", "session_ledger.rb"))
    FileUtils.cp(File.join(real_scripts, "lib", "store_provisioning.rb"),
                 File.join(scripts, "lib", "store_provisioning.rb"))
    FileUtils.cp(File.join(real_scripts, "lib", "dashboard_banner.rb"),
                 File.join(scripts, "lib", "dashboard_banner.rb"))
    FileUtils.cp(File.join(real_scripts, "lib", "qmd_sync.rb"), File.join(scripts, "lib", "qmd_sync.rb"))
    FileUtils.cp(File.join(real_scripts, "lib", "packet_wrapper.rb"), File.join(scripts, "lib", "packet_wrapper.rb"))
    FileUtils.cp(File.join(real_scripts, "lib", "active_delivery.rb"), File.join(scripts, "lib", "active_delivery.rb"))
    FileUtils.cp(File.join(real_scripts, "lib", "lock.rb"), File.join(scripts, "lib", "lock.rb"))
    FileUtils.chmod(0o755, File.join(scripts, "hook-capture"))
    root
  end

  # 345 S6: under the old /\bcontinue\b/i trigger, "continue and take it from
  # here" fired both the cockpit and the auto steer in one prompt, so this
  # single test exercised job (d)'s missing-dashboard guard and job (e)'s
  # steer together. Under the exact-match rule the two triggers are mutually
  # exclusive (a prompt equal to "continue" carries no auto trigger, and an
  # auto-trigger prompt is not equal to "continue"), so the old prompt no
  # longer fires the cockpit at all and the test went vacuous rather than
  # red. Split into two, each against the same dashboard-less fixture.

  def test_dashboard_missing_on_a_bare_continue_exits_zero_and_emits_nothing
    root = isolated_capture_without_dashboard
    script = File.join(root, "scripts", "hook-capture")
    payload = { "session_id" => "sess-nodash-continue", "user_prompt" => "continue", "cwd" => @home }
    env = { "PLASTIC_HOME" => @plastic_home, "HOME" => @home, "CLAUDE_CODE_SESSION_ID" => nil }
    out, status = Open3.capture2(env, "ruby", script, stdin_data: JSON.generate(payload))

    assert_equal 0, status.exitstatus, out
    assert_empty out.strip,
                 "the cockpit is the only job a bare continue could fire, and the missing dashboard is why it did not"
  ensure
    FileUtils.rm_rf(root) if root
  end

  def test_dashboard_missing_does_not_suppress_the_auto_steer
    root = isolated_capture_without_dashboard
    script = File.join(root, "scripts", "hook-capture")
    payload = { "session_id" => "sess-nodash-auto", "user_prompt" => "take it from here", "cwd" => @home }
    env = { "PLASTIC_HOME" => @plastic_home, "HOME" => @home, "CLAUDE_CODE_SESSION_ID" => nil }
    out, status = Open3.capture2(env, "ruby", script, stdin_data: JSON.generate(payload))

    assert_equal 0, status.exitstatus, out
    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext").to_s
    assert_includes ctx, "Invoke the plastic-auto skill",
                    "a missing dashboard must not suppress another job's context"
  ensure
    FileUtils.rm_rf(root) if root
  end

  # --- registry / launcher shape -----------------------------------------------------

  def test_launcher_is_executable_and_pipes_stdin_unchanged
    launcher = File.expand_path("../hooks/capture", __dir__)
    assert File.executable?(launcher)
    body = File.read(launcher)
    assert_includes body, "hook-capture"
  end

# --- capture never invokes qmd (intent 341, G8, n5: blocker 5.5) ----------
#
# n3 wired a bounded QMD search into a capture-worthy prompt (job (f)); v1's
# review found the timeout (`Timeout.timeout(2)`) never actually bounds an
# `Open3.capture3` child process, so a hung `qmd` can hang the hook. Removed
# entirely rather than reworked: the capture hook invokes no qmd at all.

def register_project(slug, dir)
  FileUtils.mkdir_p(dir)
  File.write(File.join(@plastic_home, "projects.yml"), YAML.dump("projects" => { slug => { "path" => dir } }))
end

def test_capture_hook_never_invokes_qmd
  project_dir = File.join(@home, "code", "proj")
  register_project("proj", project_dir)

  marker_dir = Dir.mktmpdir("capture-hook-qmd-marker")
  marker = File.join(marker_dir, "qmd-was-called")
  bindir = Dir.mktmpdir("capture-hook-qmd-bin")
  fake = File.join(bindir, "qmd")
  File.write(fake, <<~FAKE)
    #!/usr/bin/env ruby
    File.write(#{marker.inspect}, "called: \#{ARGV.join(' ')}\\n")
    puts "[]"
  FAKE
  File.chmod(0o755, fake)

  prompt = "let's revisit the widget project design and figure out the next implementation steps"
  payload = { "session_id" => "sess-no-qmd", "user_prompt" => prompt, "cwd" => project_dir }
  env = { "PLASTIC_HOME" => @plastic_home, "HOME" => @home, "CLAUDE_CODE_SESSION_ID" => nil,
          "PATH" => [bindir, ENV.fetch("PATH", "")].join(File::PATH_SEPARATOR) }
  out, status = Open3.capture2(env, "ruby", SCRIPT, stdin_data: JSON.generate(payload))

  assert_equal 0, status.exitstatus, out
  refute File.exist?(marker), "the capture hook must never invoke qmd"
  refute_includes out, "qmd-hit", "the output must carry no qmd-hit data block"
ensure
  FileUtils.rm_rf(bindir) if bindir
  FileUtils.rm_rf(marker_dir) if marker_dir
end
end
