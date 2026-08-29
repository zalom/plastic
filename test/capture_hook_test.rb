require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "yaml"
require "open3"
require_relative "../scripts/lib/session_ledger"

# Intent 298: hook-capture replaces hook-continue, hook-future-intent-check,
# and hook-auto-arm. One UserPromptSubmit process that appends a pending line
# to the session day ledger, detects "continue" and "auto" prompts, and hints
# at matching Future intents. Every job is best-effort and the hook always
# exits 0 (spec D2).
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

  def pointer_path(session)
    SessionLedger.pointer_path(@store, sid_for(session))
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

  def test_prompt_under_ten_chars_no_pending_line_heartbeat_still_rewritten
    out, status = run_hook("hi there", session: "sess-short")
    assert_equal 0, status.exitstatus
    assert_empty parsed_checklist_lines
    assert File.exist?(heartbeat_path("sess-short")), "heartbeat must still be rewritten"
    assert_empty out.strip
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

  # --- current names an intent id -------------------------------------------------

  def test_current_names_an_intent_id_no_pending_line_context_still_produced
    sid = sid_for("sess-1")
    FileUtils.mkdir_p(SessionLedger.session_tmp_dir(@store, sid))
    File.write(SessionLedger.pointer_path(@store, sid), "42--some-intent\n")

    out, status = run_hook("please continue with the important work", session: "sess-1")
    assert_equal 0, status.exitstatus, out
    assert_empty parsed_checklist_lines, "current names an intent, so no pending line"
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

  def test_automation_substring_does_not_trigger
    out, status = run_hook("what is the automation strategy here anyway", session: "sess-noauto")
    assert_equal 0, status.exitstatus, out
    if out.strip.empty?
      assert true
    else
      ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext").to_s
      refute_includes ctx, "Invoke the plastic-auto skill"
    end
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

  def test_future_intent_hint_lists_matches_from_global_and_project_store
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
    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext")
    assert_includes ctx, "Future intents related to this message"
    assert_includes ctx, "Widget global feature"
    assert_includes ctx, "Widget project feature"
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
    FileUtils.chmod(0o755, File.join(scripts, "hook-capture"))
    root
  end

  def test_dashboard_missing_still_exits_zero_other_parts_still_emitted
    root = isolated_capture_without_dashboard
    script = File.join(root, "scripts", "hook-capture")
    payload = { "session_id" => "sess-mixed", "user_prompt" => "continue and take it from here",
                "cwd" => @home }
    env = { "PLASTIC_HOME" => @plastic_home, "HOME" => @home, "CLAUDE_CODE_SESSION_ID" => nil }
    out, status = Open3.capture2(env, "ruby", script, stdin_data: JSON.generate(payload))

    assert_equal 0, status.exitstatus, out
    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext").to_s
    refute_includes ctx, "plastic-intent-continuing skill workflow",
                    "no dashboard.rb means no cockpit context"
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
end
