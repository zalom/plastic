# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "json"
require "date"
require "fileutils"
require "open3"
require_relative "../scripts/lib/session_ledger"
require_relative "../scripts/lib/session_backfill"

# Intent 301: the first-boot sweep inside hook-session-start files every
# unclosed prior day into today. Spawns the real hook against a tmp home
# (PLASTIC_TMP isolated, CLAUDE_CODE_SESSION_ID cleared).
class SessionSweepTest < Minitest::Test
  HOOK = File.expand_path("../scripts/hook-session-start", __dir__)
  TEMPLATES = File.expand_path("../templates", __dir__)

  def setup
    @home = Dir.mktmpdir("sweep-home")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
    @index = File.join(@home, "INDEX.md")
    File.write(@index, "# Index\n\n## Active\n\n## Future\n")
    @today = SessionLedger.day_id
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def day_before(n)
    (Date.strptime(@today, "%Y%m%d") - n).strftime("%Y%m%d")
  end

  def seed_day(day, *open_items)
    SessionLedger.open_day(store: @store, day: day, templates: TEMPLATES, author: "t")
    open_items.each do |summary|
      SessionLedger.append_line(SessionLedger.checklist_path(@store, day),
                                SessionLedger.checklist_line(:open, "abc", "plastic", summary),
                                header: SessionLedger.checklist_header(day))
    end
  end

  def run_hook
    out, _err, status = Open3.capture3({ "PLASTIC_TMP" => @home, "CLAUDE_CODE_SESSION_ID" => nil },
                                       "ruby", HOOK, @index, @home, "global")
    [JSON.parse(out).dig("hookSpecificOutput", "additionalContext").to_s, status.exitstatus]
  end

  def today_items
    path = SessionLedger.checklist_path(@store, @today)
    File.exist?(path) ? File.readlines(path).grep(/\A- \[/) : []
  end

  def closed?(day)
    !SessionBackfill.closed_at(SessionLedger.day_file(@store, day)).nil?
  end

  def test_one_unclosed_yesterday_is_filed_and_carried_into_today
    yesterday = day_before(1)
    seed_day(yesterday, "finish the report")
    ctx, status = run_hook
    assert_equal 0, status
    assert closed?(yesterday)
    assert_equal ["- [ ] [abc] [plastic] finish the report (carried from #{yesterday})\n"], today_items
    assert_includes ctx, "PLASTIC: filed 1 prior day ledger(s) into #{@today}"
    assert File.exist?(File.join(SessionLedger.day_dir(@store, yesterday), "outcome.md"))
  end

  def test_two_unclosed_days_are_filed_oldest_first_and_items_chain_forward
    two = day_before(2)
    one = day_before(1)
    seed_day(two, "from two days ago")
    seed_day(one, "from yesterday")
    _ctx, status = run_hook
    assert_equal 0, status
    assert closed?(two) && closed?(one)
    summaries = today_items.map { |l| SessionLedger.parse_checklist_line(l)[:summary] }
    assert_equal ["from two days ago (carried from #{two})", "from yesterday (carried from #{one})"], summaries
  end

  def test_a_closed_day_is_left_alone_and_a_reopened_day_is_filed_again
    yesterday = day_before(1)
    seed_day(yesterday, "done already")
    run_hook
    assert_equal 1, today_items.size
    before = File.read(SessionLedger.day_file(@store, yesterday))
    run_hook
    assert_equal before, File.read(SessionLedger.day_file(@store, yesterday))
    assert_equal 1, today_items.size

    SessionLedger.append_line(SessionLedger.checklist_path(@store, yesterday),
                              SessionLedger.checklist_line(:open, "abc", "plastic", "late line"))
    later = Time.now + 5
    File.utime(later, later, SessionLedger.checklist_path(@store, yesterday))
    run_hook
    assert_equal 2, today_items.size
  end

  def test_non_directory_and_non_date_names_under_sessions_are_ignored
    root = SessionLedger.sessions_root(@store)
    FileUtils.mkdir_p(root)
    File.write(File.join(root, "20260101"), "a file, not a day\n")
    FileUtils.mkdir_p(File.join(root, "notes"))
    FileUtils.mkdir_p(File.join(root, "20261340"))
    _ctx, status = run_hook
    assert_equal 0, status
    assert_empty today_items
  end

  def test_at_most_three_days_per_boot_and_the_rest_are_named
    days = (1..5).map { |n| day_before(n) }.reverse
    days.each { |d| seed_day(d, "item of #{d}") }
    ctx, status = run_hook
    assert_equal 0, status
    assert_equal 3, days.count { |d| closed?(d) }
    assert days.first(3).all? { |d| closed?(d) }, "oldest three must be filed first"
    assert_includes ctx, "2 more wait for the next boot"
  end
end
