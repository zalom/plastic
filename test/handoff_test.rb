# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/session_ledger"
require_relative "../scripts/lib/handoff"

# Intent 311: the hand-off is a pure rendering of one session's share of a
# day ledger. In process; every path is injected, nothing reads ENV.
class HandoffTest < Minitest::Test
  TEMPLATES = File.expand_path("../templates", __dir__)
  DAY = "20260830"
  SID = "b7137962"
  NOW = Time.utc(2026, 8, 30, 12, 0, 0)

  def setup
    @store = Dir.mktmpdir("handoff-store")
    SessionLedger.open_day(store: @store, day: DAY, templates: TEMPLATES, author: "t")
  end

  def teardown
    FileUtils.rm_rf(@store)
  end

  def item(state, summary, session: SID, project: "plastic")
    SessionLedger.append_line(SessionLedger.checklist_path(@store, DAY),
                              SessionLedger.checklist_line(state, session, project, summary),
                              header: SessionLedger.checklist_header(DAY))
  end

  def event(kind, summary, session: SID, at: NOW, project: "plastic")
    SessionLedger.append_line(SessionLedger.savepoint_path(@store, DAY),
                              SessionLedger.savepoint_line(kind, session, project, summary, now: at),
                              header: nil)
  end

  def render(trigger: "tick", session: SID)
    Handoff.render(store: @store, day: DAY, session: session, trigger: trigger, now: NOW)
  end

  def section(text, title)
    text.split(/^## /).find { |s| s.start_with?(title) }.to_s
  end

  # --- rendering -----------------------------------------------------------------

  def test_header_names_session_day_trigger_and_time
    text = render(trigger: "precompact")
    assert_includes text, "# Hand-off: session #{SID}, #{DAY}"
    assert_includes text, "Written 2026-08-30T12:00:00Z at precompact"
  end

  def test_only_this_sessions_items_appear_and_others_are_counted
    item(:open, "mine open")
    item(:pending, "mine pending")
    item(:done, "mine done")
    item(:open, "theirs open", session: "other111")
    item(:done, "theirs done", session: "other111")
    item(:done, "third done", session: "third333")

    text = render
    open = section(text, "Open")
    done = section(text, "Done")
    others = section(text, "Others today")

    assert_includes open, "- [plastic] mine open"
    assert_includes open, "- [plastic] mine pending"
    refute_includes open, "theirs"
    assert_includes done, "- [plastic] mine done"
    refute_includes done, "theirs"
    refute_includes done, "third"
    assert_includes others, "other111"
    assert_includes others, "1 open, 1 done"
    assert_includes others, "third333"
    assert_includes others, "0 open, 1 done"
  end

  def test_open_lists_oldest_first
    item(:open, "first")
    item(:open, "second")
    open = section(render, "Open")
    assert_operator open.index("first"), :<, open.index("second")
  end

  def test_recent_renders_this_sessions_last_ten_savepoint_lines_as_time_event_summary
    12.times { |i| event("Item", "step #{i}", at: NOW + i * 60) }
    event("Done", "theirs", session: "other111", at: NOW + 3600)
    recent = section(render, "Recent")
    refute_includes recent, "step 0"
    refute_includes recent, "step 1\n"
    assert_includes recent, "12:02Z Item step 2"
    assert_includes recent, "12:11Z Item step 11"
    refute_includes recent, "theirs"
  end

  def test_no_rendered_line_is_a_raw_ledger_line
    item(:open, "open [with] brackets")
    item(:done, "done thing")
    event("Done", "done thing")
    render.each_line do |line|
      refute_match(/\A- \[[ ~x>\-^]\] \[/, line, "raw ledger line leaked: #{line.inspect}")
      refute_match(/\A\d{4}-\d{2}-\d{2}T/, line, "raw savepoint line leaked: #{line.inspect}")
    end
  end

  def test_summary_with_brackets_survives_intact
    item(:open, "rename [a] to [b]")
    assert_includes section(render, "Open"), "- [plastic] rename [a] to [b]"
  end

  def test_resume_line_is_present
    assert_includes render, "## Resume"
    assert_includes render, "Say continue"
  end

  def test_empty_day_renders_header_and_resume_only
    text = render
    assert_includes text, "# Hand-off: session #{SID}, #{DAY}"
    assert_includes text, "## Resume"
    refute_includes text, "## Open"
    refute_includes text, "## Done"
    refute_includes text, "## Recent"
    refute_includes text, "## Others today"
  end

  def test_missing_checklist_and_savepoint_files_do_not_raise
    FileUtils.rm_f(SessionLedger.checklist_path(@store, DAY))
    FileUtils.rm_f(SessionLedger.savepoint_path(@store, DAY))
    assert_includes render, "## Resume"
  end

  def test_output_stays_under_budget_with_a_more_tail
    200.times { |i| item(:open, "open item number #{i} with a summary long enough to matter") }
    200.times { |i| item(:done, "done item number #{i} with a summary long enough to matter") }
    50.times { |i| event("Item", "event #{i}", at: NOW + i) }
    30.times { |i| item(:open, "o#{i}", session: format("s%07d", i)) }
    text = render
    assert_operator text.bytesize, :<=, Handoff::BUDGET
    assert_match(/\(\+\d+ more\)/, text)
    assert_includes text, "## Open"
  end

  def test_caps_apply_before_the_budget_and_keep_the_newest
    30.times { |i| item(:open, "o#{i}") }
    30.times { |i| item(:done, "d#{i}") }
    text = render
    assert_equal 20, section(text, "Open").scan(/^- \[/).size
    assert_equal 10, section(text, "Done").scan(/^- \[/).size
    assert_includes section(text, "Open"), "(+10 more)"
    assert_includes section(text, "Done"), "(+20 more)"
    assert_includes section(text, "Open"), "o29"
    refute_includes section(text, "Open"), "o9\n"
  end

  def test_full_caps_fit_inside_the_budget_without_trimming
    20.times { |i| item(:open, "open #{i} #{'x' * 190}") }
    10.times { |i| item(:done, "done #{i} #{'x' * 190}") }
    10.times { |i| event("Item", "event #{i} #{'x' * 190}", at: NOW + i) }
    10.times { |i| item(:open, "o", session: format("s%07d", i)) }
    text = render
    assert_operator text.bytesize, :<=, Handoff::BUDGET
    assert_equal 20, section(text, "Open").scan(/^- \[/).size
    assert_equal 10, section(text, "Done").scan(/^- \[/).size
    refute_match(/\(\+\d+ more\)/, text)
  end

  def test_long_summaries_are_clipped_to_eighty_characters
    item(:open, "a" * 200)
    line = section(render, "Open").lines.find { |l| l.start_with?("- [plastic] ") }
    assert_equal "- [plastic] #{'a' * 80}...", line.chomp
  end

  def test_unknown_trigger_raises
    assert_raises(ArgumentError) { render(trigger: "nap") }
  end

  # --- writing -----------------------------------------------------------------------

  def test_write_lands_at_the_day_path_atomically_and_returns_it
    item(:open, "mine")
    path = Handoff.write(store: @store, day: DAY, session: SID, trigger: "tick",
                         templates: TEMPLATES, now: NOW)
    assert_equal File.join(SessionLedger.day_dir(@store, DAY), "handoff--#{SID}.md"), path
    assert_equal Handoff.path_for(@store, DAY, SID), path
    assert_includes File.read(path), "mine"
    leftovers = Dir.children(SessionLedger.day_dir(@store, DAY)).grep(/\A\.handoff/)
    assert_empty leftovers, "temp file must not remain"
  end

  def test_two_concurrent_writes_for_one_session_leave_one_valid_file_and_no_residue
    50.times { |i| item(:open, "item #{i}") }
    threads = 4.times.map do
      Thread.new do
        5.times { Handoff.write(store: @store, day: DAY, session: SID, trigger: "tick", templates: TEMPLATES, now: NOW) }
      end
    end
    threads.each(&:join)
    day_dir = SessionLedger.day_dir(@store, DAY)
    assert_empty Dir.children(day_dir).grep(/\A\.handoff/), "no temp residue"
    assert_equal 1, Dir.children(day_dir).grep(/\Ahandoff--/).size
    text = File.read(Handoff.path_for(@store, DAY, SID))
    assert text.start_with?("# Hand-off: session #{SID}, #{DAY}")
    assert text.end_with?("#{Handoff::RESUME}\n"), "the file must be complete"
  end

  def test_others_is_capped_at_ten_sessions
    15.times { |i| item(:open, "o", session: format("s%07d", i)) }
    others = section(render, "Others today")
    assert_equal 10, others.scan(/^- s/).size
    assert_includes others, "(+5 more)"
  end

  def test_write_opens_a_day_that_does_not_exist_yet
    tomorrow = "20260831"
    path = Handoff.write(store: @store, day: tomorrow, session: SID, trigger: "close",
                         templates: TEMPLATES, now: NOW)
    assert File.exist?(SessionLedger.day_file(@store, tomorrow)), "the day must be scaffolded"
    assert File.exist?(path)
  end

  def test_write_regenerates_in_full_on_every_call
    item(:open, "first")
    Handoff.write(store: @store, day: DAY, session: SID, trigger: "tick", templates: TEMPLATES, now: NOW)
    SessionLedger.set_state(SessionLedger.checklist_path(@store, DAY), from: :open, to: :done, session: SID)
    path = Handoff.write(store: @store, day: DAY, session: SID, trigger: "tick", templates: TEMPLATES, now: NOW)
    text = File.read(path)
    refute_includes section(text, "Open"), "first"
    assert_includes section(text, "Done"), "first"
  end

  # --- the pointer day -------------------------------------------------------------

  def test_day_for_returns_the_pointer_day_and_today_when_no_pointer_or_an_intent_pointer
    assert_equal DAY, Handoff.day_for(@store, SID, today: DAY)
    SessionLedger.ensure_tmp_root(@store)
    FileUtils.mkdir_p(SessionLedger.session_tmp_dir(@store, SID))
    File.write(SessionLedger.pointer_path(@store, SID), "20260829\n")
    assert_equal "20260829", Handoff.day_for(@store, SID, today: DAY)
    File.write(SessionLedger.pointer_path(@store, SID), "311--handoff-and-day-summary\n")
    assert_equal DAY, Handoff.day_for(@store, SID, today: DAY)
  end
end

# The CLI: a thin wrapper, driven as a subprocess with an explicit store.
class WriteHandoffCliTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/write-handoff", __dir__)
  TEMPLATES = File.expand_path("../templates", __dir__)
  DAY = "20260830"

  def setup
    @home = Dir.mktmpdir("write-handoff-home")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def run_cli(*args)
    env = { "CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_HOME" => @home }
    out = IO.popen(env, [RbConfig.ruby, SCRIPT, *args], err: [:child, :out], &:read)
    [out, $?.exitstatus]
  end

  def test_prints_the_path_and_writes_the_file
    out, status = run_cli("--store", @store, "--day", DAY, "--session", "abcdef12",
                          "--trigger", "tick", "--templates", TEMPLATES)
    assert_equal 0, status, out
    path = out.strip
    assert_equal Handoff.path_for(@store, DAY, "abcdef12"), path
    assert File.exist?(path)
  end

  def test_missing_trigger_exits_2
    _out, status = run_cli("--store", @store, "--day", DAY, "--session", "abcdef12", "--templates", TEMPLATES)
    assert_equal 2, status
  end

  def test_bad_trigger_exits_2_and_writes_nothing
    out, status = run_cli("--store", @store, "--day", DAY, "--session", "abcdef12",
                          "--trigger", "nap", "--templates", TEMPLATES)
    assert_equal 2, status, out
    refute File.exist?(Handoff.path_for(@store, DAY, "abcdef12"))
  end

  def test_bad_day_exits_2
    _out, status = run_cli("--store", @store, "--day", "2026-08-30", "--session", "abcdef12",
                           "--trigger", "tick", "--templates", TEMPLATES)
    assert_equal 2, status
  end

  def test_trailing_flag_without_value_exits_2
    _out, status = run_cli("--store", @store, "--trigger", "tick", "--day")
    assert_equal 2, status
  end

  def test_the_script_is_a_thin_cli_over_the_lib
    src = File.read(SCRIPT)
    assert_includes src, 'require_relative "lib/handoff"'
    assert_operator src.lines.size, :<=, 120
  end
end
