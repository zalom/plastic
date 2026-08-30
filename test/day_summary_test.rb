# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../scripts/lib/session_ledger"
require_relative "../scripts/lib/day_summary"

# Intent 311: the day summary is what SessionStart injects, a bounded
# rendering of the day ledger, the live locks, and the heartbeats. In
# process; every path is injected, nothing reads ENV.
class DaySummaryTest < Minitest::Test
  TEMPLATES = File.expand_path("../templates", __dir__)
  DAY = "20260830"
  SELF = "b7137962"
  NOW = Time.utc(2026, 8, 30, 12, 0, 0)

  def setup
    @home = Dir.mktmpdir("day-summary-home")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
    SessionLedger.open_day(store: @store, day: DAY, templates: TEMPLATES, author: "t")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  # --- fixtures --------------------------------------------------------------------

  def item(state, summary, session: SELF, project: "plastic")
    SessionLedger.append_line(SessionLedger.checklist_path(@store, DAY),
                              SessionLedger.checklist_line(state, session, project, summary),
                              header: SessionLedger.checklist_header(DAY))
  end

  def event(kind, summary, session: SELF, at: NOW, project: "plastic")
    SessionLedger.append_line(SessionLedger.savepoint_path(@store, DAY),
                              SessionLedger.savepoint_line(kind, session, project, summary, now: at),
                              header: nil)
  end

  def index(path, active: [], future: [])
    body = +"# Index\n\n## Active\n"
    active.each { |d| body << "- [#{d}](store/#{d}/#{d}.md) - tags\n" }
    body << "\n## Future\n"
    future.each { |d| body << "- [#{d}](store/#{d}/#{d}.md) - tags\n" }
    File.write(path, body)
  end

  def intent(store, dirname, lock_age: nil, savepoint: nil, run_mode: "auto")
    dir = File.join(store, dirname)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{dirname}.md"), "---\nid: \"#{dirname.split('--').first}\"\n---\n")
    File.write(File.join(dir, "savepoint.md"), savepoint) if savepoint
    if lock_age
      lock = File.join(dir, "delivery.lock")
      data = { "type" => "delivery", "owner_session" => "x" }
      data["run_mode"] = run_mode if run_mode
      File.write(lock, JSON.generate(data))
      FileUtils.touch(lock, mtime: NOW - lock_age)
    end
    dir
  end

  def session_tmp(sid, heartbeat:, current: DAY)
    SessionLedger.ensure_tmp_root(@store)
    dir = SessionLedger.session_tmp_dir(@store, sid)
    FileUtils.mkdir_p(dir)
    File.write(SessionLedger.pointer_path(@store, sid), "#{current}\n") if current
    path = SessionLedger.heartbeat_path(@store, sid)
    if heartbeat.is_a?(Time)
      File.write(path, "#{heartbeat.utc.iso8601}\n")
    else
      File.write(path, "")
      FileUtils.touch(path, mtime: NOW - 120)
    end
  end

  def seed_everything
    item(:open, "mine open")
    item(:pending, "mine pending")
    item(:done, "mine done")
    item(:open, "theirs open", session: "other111", project: "demo")
    7.times { |i| event("Done", "done #{i}", at: NOW - (7 - i) * 60) }
    event("Item", "not done", at: NOW)

    index(File.join(@home, "INDEX.md"), active: %w[40--live 41--nolock 42--stale 99--gone], future: %w[43--future])
    intent(@store, "40--live", lock_age: 60,
                   savepoint: "2026-08-30T11:00:00Z  How  plan.md created\n2026-08-30T11:30:00Z  Exec  tests red\n")
    intent(@store, "41--nolock", savepoint: "2026-08-30T11:00:00Z  Why  spec.md created\n")
    intent(@store, "42--stale", lock_age: 7200, savepoint: "2026-08-30T09:00:00Z  Exec  stuck\n")
    intent(@store, "43--future", lock_age: 60)

    project_store = File.join(@home, "projects", "demo", "store")
    FileUtils.mkdir_p(project_store)
    index(File.join(@home, "projects", "demo", "INDEX.md"), active: %w[7--proj])
    intent(project_store, "7--proj", lock_age: 30, savepoint: "2026-08-30T11:45:00Z  Exec  executor running\n")

    session_tmp(SELF, heartbeat: NOW)
    session_tmp("fresh111", heartbeat: NOW - 600)
    session_tmp("stale222", heartbeat: NOW - 7200)
    session_tmp("empty333", heartbeat: :empty, current: "311--handoff-and-day-summary")
  end

  def build(session: SELF, ttl: 3600)
    DaySummary.build(store: @store, day: DAY, session: session, home: @home, now: NOW, heartbeat_ttl: ttl)
  end

  def part(text, title)
    text.split(/^(?=[A-Z][^\n]*:\n)/).find { |s| s.start_with?(title) }.to_s
  end

  # --- shape -----------------------------------------------------------------------

  def test_all_four_parts_render_under_the_day_heading
    seed_everything
    text = build
    assert text.start_with?("Day summary #{DAY}:"), text
    %w[Open: Done,\ last\ five: Live\ auto\ intents: Other\ active\ sessions:].each do |heading|
      assert_includes text, heading
    end
  end

  def test_empty_day_and_store_render_nothing
    assert_equal "", build
  end

  def test_missing_sessions_dir_and_index_do_not_raise
    FileUtils.rm_rf(SessionLedger.sessions_root(@store))
    assert_equal "", build
    session_tmp("fresh111", heartbeat: NOW - 60)
    assert_includes build, "Other active sessions:"
  end

  def test_parts_are_omitted_when_empty
    item(:open, "only open")
    text = build
    assert_includes text, "Open:"
    refute_includes text, "Done, last five:"
    refute_includes text, "Live auto intents:"
    refute_includes text, "Other active sessions:"
  end

  # --- open ------------------------------------------------------------------------

  def test_open_lists_every_sessions_open_and_pending_items_with_session_and_project
    seed_everything
    open = part(build, "Open:")
    assert_includes open, "- [#{SELF}] [plastic] mine open"
    assert_includes open, "- [#{SELF}] [plastic] mine pending"
    assert_includes open, "- [other111] [demo] theirs open"
    refute_includes open, "mine done"
  end

  def test_open_is_capped_at_ten_with_a_more_tail
    15.times { |i| item(:open, "o#{i}") }
    open = part(build, "Open:")
    assert_equal 10, open.scan(/^- \[/).size
    assert_includes open, "(+5 more)"
  end

  # --- done ------------------------------------------------------------------------

  def test_done_shows_the_last_five_done_lines_in_order
    seed_everything
    done = part(build, "Done, last five:")
    refute_includes done, "done 0"
    refute_includes done, "done 1\n"
    assert_includes done, "done 2"
    assert_includes done, "done 6"
    refute_includes done, "not done"
    assert_operator done.index("done 2"), :<, done.index("done 6")
  end

  # --- live intents ----------------------------------------------------------------

  def test_live_intents_are_active_with_a_fresh_lock_across_every_store
    seed_everything
    live = part(build, "Live auto intents:")
    assert_includes live, "- 40 live: 2026-08-30T11:30:00Z  Exec  tests red"
    assert_includes live, "- 7 proj: 2026-08-30T11:45:00Z  Exec  executor running"
    refute_includes live, "41 nolock", "Active without a lock is not live"
    refute_includes live, "42 stale", "a stale lock is not live"
    refute_includes live, "43 future", "a Future intent is never live"
    refute_includes live, "99"
  end

  def test_guided_lock_is_excluded_and_a_lock_without_run_mode_counts_as_auto
    index(File.join(@home, "INDEX.md"), active: %w[44--guided 45--legacy])
    intent(@store, "44--guided", lock_age: 10, run_mode: "guided", savepoint: "2026-08-30T11:00:00Z  Exec  by hand\n")
    intent(@store, "45--legacy", lock_age: 10, run_mode: nil, savepoint: "2026-08-30T11:00:00Z  Exec  old team\n")
    live = part(build, "Live auto intents:")
    refute_includes live, "44 guided"
    assert_includes live, "- 45 legacy: 2026-08-30T11:00:00Z  Exec  old team"
  end

  def test_long_summaries_and_savepoint_lines_are_clipped
    item(:open, "b" * 200)
    index(File.join(@home, "INDEX.md"), active: %w[46--long])
    intent(@store, "46--long", lock_age: 10, savepoint: "2026-08-30T11:00:00Z  Exec  #{'y' * 200}\n")
    text = build
    assert_includes text, "- [#{SELF}] [plastic] #{'b' * 80}..."
    assert_equal 100, part(text, "Live auto intents:").lines[1].chomp.sub("- 46 long: ", "").length
  end

  def test_full_caps_fit_inside_the_budget_without_trimming
    10.times { |i| item(:open, "open #{i} #{'x' * 190}", session: format("s%07d", i)) }
    5.times { |i| event("Done", "done #{i} #{'x' * 190}", at: NOW + i) }
    index(File.join(@home, "INDEX.md"), active: (1..5).map { |i| "#{i}--slug-#{i}" })
    (1..5).each { |i| intent(@store, "#{i}--slug-#{i}", lock_age: 5, savepoint: "2026-08-30T11:00:00Z  Exec  #{'z' * 150}\n") }
    10.times { |i| session_tmp(format("h%07d", i), heartbeat: NOW - i, current: "311--handoff-and-day-summary") }
    text = build
    assert_operator text.bytesize, :<=, DaySummary::BUDGET
    refute_match(/\(\+\d+ more\)/, text)
  end

  def test_live_intent_without_a_savepoint_renders_a_placeholder
    index(File.join(@home, "INDEX.md"), active: %w[50--bare])
    intent(@store, "50--bare", lock_age: 10)
    assert_includes part(build, "Live auto intents:"), "- 50 bare: (no savepoint yet)"
  end

  # --- other sessions --------------------------------------------------------------

  def test_other_sessions_excludes_self_and_stale_heartbeats
    seed_everything
    others = part(build, "Other active sessions:")
    refute_includes others, SELF
    refute_includes others, "stale222"
    assert_includes others, "- fresh111 (10m ago, on #{DAY})"
    assert_includes others, "- empty333 (2m ago, on 311--handoff-and-day-summary)"
  end

  def test_heartbeat_ttl_is_honored
    seed_everything
    others = part(build(ttl: 300), "Other active sessions:")
    refute_includes others, "fresh111"
    assert_includes others, "empty333"
  end

  # --- invariants ------------------------------------------------------------------

  def test_no_rendered_line_is_a_raw_ledger_line
    seed_everything
    item(:open, "rename [a] to [b]")
    build.each_line do |line|
      refute_match(/\A- \[[ ~x>\-^]\] \[/, line, "raw ledger line leaked: #{line.inspect}")
      refute_match(/\A\d{4}-\d{2}-\d{2}T/, line, "raw savepoint line leaked: #{line.inspect}")
    end
  end

  def test_output_stays_under_budget_with_a_more_tail
    40.times { |i| item(:open, "open item number #{i} with a summary long enough to fill the block quickly", session: format("s%07d", i)) }
    60.times { |i| session_tmp(format("h%07d", i), heartbeat: NOW - i) }
    index(File.join(@home, "INDEX.md"), active: (1..20).map { |i| "#{i}--intent-with-a-long-slug-#{i}" })
    (1..20).each { |i| intent(@store, "#{i}--intent-with-a-long-slug-#{i}", lock_age: 5, savepoint: "2026-08-30T11:00:00Z  Exec  #{'x' * 150}\n") }
    text = build
    assert_operator text.bytesize, :<=, DaySummary::BUDGET
    assert_match(/\(\+\d+ more\)/, text)
    assert_includes text, "Open:"
  end
end

# The CLI: a thin wrapper, driven as a subprocess with an explicit store.
class DaySummaryCliTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/day-summary", __dir__)
  TEMPLATES = File.expand_path("../templates", __dir__)
  DAY = "20260830"

  def setup
    @home = Dir.mktmpdir("day-summary-cli-home")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
    SessionLedger.open_day(store: @store, day: DAY, templates: TEMPLATES, author: "t")
    SessionLedger.append_line(SessionLedger.checklist_path(@store, DAY),
                              SessionLedger.checklist_line(:open, "abcdef12", "plastic", "cli open"),
                              header: SessionLedger.checklist_header(DAY))
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def run_cli(*args)
    env = { "CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_HOME" => @home }
    out = IO.popen(env, [RbConfig.ruby, SCRIPT, *args], err: [:child, :out], &:read)
    [out, $?.exitstatus]
  end

  def test_prints_the_block
    out, status = run_cli("--store", @store, "--day", DAY, "--session", "zzzzzzzz", "--home", @home)
    assert_equal 0, status, out
    assert_includes out, "Day summary #{DAY}:"
    assert_includes out, "- [abcdef12] [plastic] cli open"
  end

  def test_bad_day_exits_2
    _out, status = run_cli("--store", @store, "--day", "nope")
    assert_equal 2, status
  end

  def test_the_script_is_a_thin_cli_over_the_lib
    src = File.read(SCRIPT)
    assert_includes src, 'require_relative "lib/day_summary"'
    assert_operator src.lines.size, :<=, 120
  end
end
