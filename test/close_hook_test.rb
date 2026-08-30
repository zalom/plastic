# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../scripts/lib/session_ledger"
require_relative "../scripts/lib/session_close"

# Intent 301: the per-session close. The library is exercised in process with
# a recording spawner; the script is spawned once for stdin handling, with
# PLASTIC_HOME and PLASTIC_TMP isolated and CLAUDE_CODE_SESSION_ID cleared.
class CloseHookTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/hook-close", __dir__)
  TEMPLATES = File.expand_path("../templates", __dir__)
  TODAY = "20260829"
  YESTERDAY = "20260828"
  SID = "b7137962-dead-beef"
  SHORT = "b7137962"

  def setup
    @home = Dir.mktmpdir("close-home")
    @tmp = Dir.mktmpdir("close-scratch")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
    SessionLedger.open_day(store: @store, day: TODAY, templates: TEMPLATES, author: "t")
    @spawned = []
    @spawner = ->(args) { @spawned << args }
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@tmp)
  end

  def append(day, state, summary, session: SHORT)
    SessionLedger.append_line(SessionLedger.checklist_path(@store, day),
                              SessionLedger.checklist_line(state, session, "plastic", summary),
                              header: SessionLedger.checklist_header(day))
  end

  def markers(day)
    File.readlines(SessionLedger.checklist_path(@store, day)).grep(/\A- \[/).map { |l| l[0, 5] }
  end

  def pointer(day)
    SessionLedger.ensure_tmp_root(@store)
    FileUtils.mkdir_p(SessionLedger.session_tmp_dir(@store, SHORT))
    File.write(SessionLedger.pointer_path(@store, SHORT), "#{day}\n")
    File.write(SessionLedger.heartbeat_path(@store, SHORT), "2026-08-29T10:00:00Z\n")
  end

  def run_close(reason: "other", session_id: SID)
    payload = { "session_id" => session_id, "cwd" => @home }
    payload["reason"] = reason unless reason.nil?
    SessionClose.run(payload: payload, store: @store, today: TODAY, spawner: @spawner)
  end

  def test_clear_and_resume_change_nothing
    append(TODAY, :pending, "keep me")
    pointer(TODAY)
    %w[clear resume].each do |reason|
      run_close(reason: reason)
      assert_equal ["- [~]"], markers(TODAY)
      assert File.exist?(SessionLedger.pointer_path(@store, SHORT)), "pointer removed on #{reason}"
    end
    assert_empty @spawned
  end

  def test_other_and_missing_reason_drop_only_this_sessions_pending_lines
    append(TODAY, :pending, "mine")
    append(TODAY, :pending, "theirs", session: "other1")
    append(TODAY, :open, "mine open")
    pointer(TODAY)
    report = run_close(reason: nil)
    assert_equal 1, report[:dropped]
    assert_equal ["- [-]", "- [~]", "- [ ]"], markers(TODAY)
    assert_includes File.read(SessionLedger.savepoint_path(@store, TODAY)), "dropped 1 pending lines at close"
  end

  def test_no_note_when_nothing_was_pending
    append(TODAY, :open, "mine open")
    pointer(TODAY)
    run_close
    refute File.exist?(SessionLedger.savepoint_path(@store, TODAY))
  end

  def test_removes_the_session_tmp_dir_and_tolerates_its_absence
    pointer(TODAY)
    report = run_close
    assert report[:removed_tmp]
    refute Dir.exist?(SessionLedger.session_tmp_dir(@store, SHORT))
    report = run_close
    assert_nil report[:spawned]
    assert_equal 0, report[:dropped]
  end

  def test_pointer_day_before_today_spawns_the_filer_with_carry_to_today
    SessionLedger.open_day(store: @store, day: YESTERDAY, templates: TEMPLATES, author: "t")
    append(YESTERDAY, :pending, "late night")
    pointer(YESTERDAY)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    report = run_close
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_equal ["--day", YESTERDAY, "--carry-to", TODAY, "--store", @store], report[:spawned]
    assert_equal [report[:spawned]], @spawned
    assert_equal ["- [-]"], markers(YESTERDAY)
    assert_operator elapsed, :<, 3
  end

  def test_pointer_naming_an_intent_touches_no_day_ledger
    append(TODAY, :pending, "mine")
    SessionLedger.ensure_tmp_root(@store)
    FileUtils.mkdir_p(SessionLedger.session_tmp_dir(@store, SHORT))
    File.write(SessionLedger.pointer_path(@store, SHORT), "297\n")
    run_close
    # An intent pointer means the day ledger is still today's for the drop of
    # this session's pending lines; the tmp dir goes either way.
    refute Dir.exist?(SessionLedger.session_tmp_dir(@store, SHORT))
    assert_empty @spawned
  end

  # --- the hand-off at close (intent 311, spec D6) ------------------------------------

  def run_close_with_handoff(reason: "other", handoff:)
    payload = { "session_id" => SID, "cwd" => @home }
    payload["reason"] = reason unless reason.nil?
    SessionClose.run(payload: payload, store: @store, today: TODAY, spawner: @spawner, handoff: handoff)
  end

  def test_close_hands_off_the_pointer_day_before_removing_the_tmp_dir
    pointer(YESTERDAY)
    calls = []
    recorder = lambda do |store, day, session|
      calls << [store, day, session, File.exist?(SessionLedger.pointer_path(@store, SHORT))]
    end
    run_close_with_handoff(handoff: recorder)
    assert_equal [[@store, YESTERDAY, SHORT, true]], calls
    refute Dir.exist?(SessionLedger.session_tmp_dir(@store, SHORT))
  end

  def test_close_without_a_pointer_hands_off_today
    calls = []
    run_close_with_handoff(handoff: ->(_s, day, _sid) { calls << day })
    assert_equal [TODAY], calls
  end

  def test_clear_and_resume_never_hand_off
    pointer(TODAY)
    calls = []
    %w[clear resume].each { |reason| run_close_with_handoff(reason: reason, handoff: ->(*a) { calls << a }) }
    assert_empty calls
  end

  def test_pointer_naming_an_intent_never_hands_off
    SessionLedger.ensure_tmp_root(@store)
    FileUtils.mkdir_p(SessionLedger.session_tmp_dir(@store, SHORT))
    File.write(SessionLedger.pointer_path(@store, SHORT), "297\n")
    calls = []
    run_close_with_handoff(handoff: ->(*a) { calls << a })
    assert_empty calls
  end

  def test_handoff_failure_is_swallowed_and_the_rest_of_close_runs
    append(TODAY, :pending, "mine")
    pointer(TODAY)
    report = run_close_with_handoff(handoff: ->(*) { raise IOError, "disk full" })
    assert_equal 1, report[:dropped]
    assert report[:removed_tmp]
  end

  def test_default_handoff_writes_the_file_with_the_close_trigger
    pointer(TODAY)
    append(TODAY, :open, "mine open")
    handoff = SessionClose.default_handoff(TEMPLATES)
    run_close_with_handoff(handoff: handoff)
    path = File.join(SessionLedger.day_dir(@store, TODAY), "handoff--#{SHORT}.md")
    assert File.exist?(path), "the default hand-off must write the day file"
    assert_includes File.read(path), "at close"
    assert_includes File.read(path), "mine open"
  end

  def test_script_writes_the_handoff_for_a_real_payload
    pointer(TODAY)
    append(TODAY, :open, "mine open")
    env = { "CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_HOME" => @home, "PLASTIC_TMP" => @tmp, "HOME" => @tmp }
    IO.popen(env, [RbConfig.ruby, SCRIPT, @home], "r+", err: [:child, :out]) do |io|
      io.write(JSON.generate("session_id" => SID, "cwd" => @home, "reason" => "other"))
      io.close_write
      io.read
    end
    assert_equal 0, $?.exitstatus
    path = File.join(SessionLedger.day_dir(@store, TODAY), "handoff--#{SHORT}.md")
    assert File.exist?(path), "hook-close must write the hand-off"
    assert_includes File.read(path), "at close"
  end

  def test_script_reads_stdin_and_the_store_from_argv_and_ignores_malformed_input
    append(TODAY, :pending, "mine")
    pointer(TODAY)
    env = { "CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_HOME" => @home, "PLASTIC_TMP" => @tmp, "HOME" => @tmp }
    out = IO.popen(env, [RbConfig.ruby, SCRIPT, @home], "r+", err: [:child, :out]) do |io|
      io.write("{not json")
      io.close_write
      io.read
    end
    assert_equal 0, $?.exitstatus, out
    assert_equal "", out
    assert_equal ["- [~]"], markers(TODAY)

    out = IO.popen(env, [RbConfig.ruby, SCRIPT, @home], "r+", err: [:child, :out]) do |io|
      io.write(JSON.generate("session_id" => SID, "reason" => "other", "cwd" => @home))
      io.close_write
      io.read
    end
    assert_equal 0, $?.exitstatus, out
    assert_equal ["- [-]"], markers(TODAY)
    refute Dir.exist?(SessionLedger.session_tmp_dir(@store, SHORT))
    refute Dir.exist?(File.join(@tmp, ".plastic")), "wrote under HOME instead of argv"
  end
end
