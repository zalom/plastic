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
