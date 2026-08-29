# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/session_ledger"

# Intent 301: scripts/file-session-intent, the day filer. Drives the real
# script as a subprocess, hermetic: Dir.mktmpdir store, PLASTIC_HOME and
# PLASTIC_TMP isolated, CLAUDE_CODE_SESSION_ID cleared.
class FileSessionIntentTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/file-session-intent", __dir__)
  TEMPLATES = File.expand_path("../templates", __dir__)
  DAY = "20260828"
  NEXT = "20260829"

  def setup
    @home = Dir.mktmpdir("fsi-home")
    @tmp = Dir.mktmpdir("fsi-scratch")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
    SessionLedger.open_day(store: @store, day: DAY, templates: TEMPLATES, author: "t")
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@tmp)
  end

  def run_filer(*args)
    env = { "CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_HOME" => @home, "PLASTIC_TMP" => @tmp }
    out = IO.popen(env, [RbConfig.ruby, SCRIPT, "--store", @store, "--templates", TEMPLATES, *args],
                   err: [:child, :out], &:read)
    [out, $?.exitstatus]
  end

  def append(day, state, summary, session: "abc")
    path = SessionLedger.checklist_path(@store, day)
    SessionLedger.append_line(path, SessionLedger.checklist_line(state, session, "plastic", summary),
                              header: SessionLedger.checklist_header(day))
  end

  def markers(day)
    File.readlines(SessionLedger.checklist_path(@store, day)).grep(/\A- \[/).map { |l| l[0, 5] }
  end

  def day_file(day)
    File.read(SessionLedger.day_file(@store, day))
  end

  def docs(day)
    dir = SessionLedger.day_dir(@store, day)
    %w[spec.md plan.md actions/ACTION_1.md outcome.md].map { |n| File.join(dir, n) }
  end

  def seed_full_day
    append(DAY, :done, "shipped one")
    append(DAY, :done, "shipped two")
    append(DAY, :open, "still open")
    append(DAY, :pending, "never acted on")
  end

  def test_files_a_day_and_carries_the_open_item_once
    seed_full_day
    out, status = run_filer("--day", DAY, "--carry-to", NEXT)
    assert_equal 0, status, out
    assert_equal "filed #{DAY}", out.strip
    docs(DAY).each { |p| assert File.exist?(p), "missing #{p}"; refute_includes File.read(p), "plastic:placeholder" }
    assert_equal ["- [x]", "- [x]", "- [>]", "- [-]"], markers(DAY)
    next_lines = File.readlines(SessionLedger.checklist_path(@store, NEXT)).grep(/\A- \[/)
    assert_equal 1, next_lines.size
    assert_equal "- [ ] [abc] [plastic] still open (carried from #{DAY})\n", next_lines.first
    assert_match(/^closed: \d{4}-\d{2}-\d{2}T/, day_file(DAY))
    assert_includes File.read(SessionLedger.savepoint_path(@store, DAY)), "carried 1 items to #{NEXT}"
    assert_includes File.read(SessionLedger.savepoint_path(@store, NEXT)), "received 1 items from #{DAY}"
  end

  def test_rerun_after_success_is_skipped_and_leaves_files_identical
    seed_full_day
    run_filer("--day", DAY, "--carry-to", NEXT)
    before = docs(DAY).map { |p| File.binread(p) } + [File.binread(SessionLedger.checklist_path(@store, NEXT))]
    out, status = run_filer("--day", DAY, "--carry-to", NEXT)
    assert_equal 0, status
    assert_equal "skipped #{DAY}: closed", out.strip
    after = docs(DAY).map { |p| File.binread(p) } + [File.binread(SessionLedger.checklist_path(@store, NEXT))]
    assert_equal before, after
  end

  def test_a_day_with_lines_newer_than_its_close_is_filed_again
    seed_full_day
    run_filer("--day", DAY, "--carry-to", NEXT)
    append(DAY, :done, "late arrival")
    path = SessionLedger.checklist_path(@store, DAY)
    later = Time.now + 5
    File.utime(later, later, path)
    out, status = run_filer("--day", DAY, "--carry-to", NEXT)
    assert_equal 0, status
    assert_equal "filed #{DAY}", out.strip
    assert_includes File.read(File.join(SessionLedger.day_dir(@store, DAY), "spec.md")), "late arrival"
  end

  def test_rerun_from_a_crash_between_carry_append_and_source_flip_carries_nothing_twice
    append(DAY, :open, "half carried")
    SessionLedger.open_day(store: @store, day: NEXT, templates: TEMPLATES, author: "t")
    append(NEXT, :open, "half carried (carried from #{DAY})")
    out, status = run_filer("--day", DAY, "--carry-to", NEXT)
    assert_equal 0, status, out
    next_lines = File.readlines(SessionLedger.checklist_path(@store, NEXT)).grep(/half carried/)
    assert_equal 1, next_lines.size
    assert_equal ["- [>]"], markers(DAY)
  end

  def test_an_item_carried_three_days_keeps_one_suffix_within_the_cap
    days = %w[20260825 20260826 20260827 20260828]
    long = "x" * 190
    SessionLedger.open_day(store: @store, day: days[0], templates: TEMPLATES, author: "t")
    append(days[0], :open, long)
    days.each_cons(2) do |from, to|
      _out, status = run_filer("--day", from, "--carry-to", to)
      assert_equal 0, status
    end
    final = File.readlines(SessionLedger.checklist_path(@store, days.last)).grep(/\A- \[ \]/).first
    parsed = SessionLedger.parse_checklist_line(final)
    assert_equal 1, parsed[:summary].scan("(carried from").size
    assert_operator parsed[:summary].length, :<=, 200
  end

  def test_without_carry_to_open_lines_stay_open_and_the_day_still_closes
    seed_full_day
    out, status = run_filer("--day", DAY)
    assert_equal 0, status, out
    assert_equal ["- [x]", "- [x]", "- [ ]", "- [-]"], markers(DAY)
    assert_match(/^closed: /, day_file(DAY))
  end

  def test_leaves_no_filing_temp_files_behind
    seed_full_day
    run_filer("--day", DAY, "--carry-to", NEXT)
    leftovers = Dir.glob(File.join(SessionLedger.day_dir(@store, DAY), "**", ".filing-*"), File::FNM_DOTMATCH)
    assert_empty leftovers
  end

  def test_invalid_day_exits_2_and_writes_nothing
    out, status = run_filer("--day", "20261340")
    assert_equal 2, status, out
    refute File.exist?(File.join(SessionLedger.day_dir(@store, "20261340"), "spec.md"))
  end

  def test_carry_target_is_scaffolded_with_the_session_author
    append(DAY, :open, "carry me")
    _out, status = run_filer("--day", DAY, "--carry-to", NEXT)
    assert_equal 0, status
    assert_match(/^author: session$/, day_file(NEXT))
  end

  def test_day_without_a_checklist_is_filed_as_abandoned
    out, status = run_filer("--day", DAY)
    assert_equal 0, status, out
    outcome = File.read(File.join(SessionLedger.day_dir(@store, DAY), "outcome.md"))
    assert outcome.start_with?("---\ndisposition: abandoned\n---\n")
  end
end
