# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/backup/daily"

# The two backups of a day: the first call of the day takes the start-of-day
# backup of every store, and each session end after it replaces the day's
# end-of-day backup. The day is the calendar day of the clock, in its offset.
class GraphBackupDailyTest < Plastic::TestCase
  include BackupHomes
  include BackupTriggers

  Daily = Plastic::Graph::Backup::Daily

  YESTERDAY = Time.new(2026, 1, 1, 18, 0, 0, "+01:00")
  MORNING = Time.new(2026, 1, 2, 9, 0, 0, "+01:00")
  NOON = Time.new(2026, 1, 2, 12, 0, 0, "+01:00")
  EVENING = Time.new(2026, 1, 2, 18, 0, 0, "+01:00")

  def daily(home, now, session_end: false) = Daily.new(home:, now:).then { |day| session_end ? day.end_session : day.begin_day }

  def backed_up_yesterday = fresh_home.tap { |home| %w[alpha beta].each { |slug| backup_at(home, YESTERDAY, slug:) } }

  def damage(home, slug = "alpha")
    Plastic::Graph::Database::ConnectionPool.release(File.join(home, "stores", slug))
    File.write(store_file(home, "work_graph", slug), "not a database")
  end

  def test_the_first_call_of_a_day_backs_up_every_store_with_the_reason_start_of_day
    home = backed_up_yesterday
    add_intent(home)
    daily(home, MORNING)

    assert_equal [[nil, "start of day"], [nil, "start of day"]], [backup_reasons(home, "alpha"), backup_reasons(home, "beta")]
  end

  def test_a_store_that_did_not_change_still_takes_its_start_of_day_backup
    home = backed_up_yesterday
    daily(home, MORNING)

    assert_equal [nil, "start of day"], backup_reasons(home, "beta")
  end

  def test_a_later_call_of_the_same_day_takes_none
    home = backed_up_yesterday
    daily(home, MORNING)
    add_intent(home)
    daily(home, NOON)

    assert_equal [nil, "start of day"], backup_reasons(home)
  end

  def test_a_start_of_day_backup_of_the_day_before_does_not_count_for_today
    home = fresh_home
    daily(home, YESTERDAY)
    daily(home, MORNING)

    assert_equal ["start of day", "start of day"], backup_reasons(home)
  end

  def test_the_day_turns_at_midnight_of_the_clock_offset_not_of_utc
    home = fresh_home
    daily(home, Time.new(2026, 1, 2, 23, 30, 0, "+01:00"))
    daily(home, Time.new(2026, 1, 3, 0, 30, 0, "+01:00"))

    assert_equal ["start of day", "start of day"], backup_reasons(home)
  end

  def test_a_session_end_after_the_start_of_day_backup_takes_an_end_of_day_backup
    home = fresh_home
    daily(home, MORNING)
    daily(home, EVENING, session_end: true)

    assert_equal ["start of day", "end of day"], backup_reasons(home)
  end

  def test_a_session_end_replaces_the_end_of_day_backup_of_a_store_that_changed
    home = fresh_home
    daily(home, MORNING)
    daily(home, NOON, session_end: true)
    add_intent(home)
    daily(home, EVENING, session_end: true)

    assert_equal [stamp(MORNING), stamp(EVENING)], folder_names(home)
  end

  def test_a_session_end_writes_nothing_for_a_store_its_end_of_day_backup_holds
    home = fresh_home
    daily(home, MORNING)
    daily(home, NOON, session_end: true)
    daily(home, EVENING, session_end: true)

    assert_equal [stamp(MORNING), stamp(NOON)], folder_names(home)
  end

  def test_a_session_end_that_is_the_first_call_of_the_day_takes_only_the_start_of_day_backup
    home = fresh_home
    daily(home, EVENING, session_end: true)

    assert_equal ["start of day"], backup_reasons(home)
  end

  def test_a_failed_end_of_day_backup_keeps_the_earlier_one
    home = fresh_home
    daily(home, MORNING)
    daily(home, NOON, session_end: true)
    damage(home)
    failures = daily(home, EVENING, session_end: true)

    assert_equal [["alpha"], [stamp(MORNING), stamp(NOON)]], [failures.map(&:slug), folder_names(home)]
  end

  def test_a_damaged_store_is_named_and_the_other_stores_are_still_backed_up
    home = fresh_home
    damage(home)
    failures = daily(home, MORNING)

    assert_equal [[["alpha", true]], ["start of day"]], [failures.map { |failure| [failure.slug, failure.reason.include?("work_graph")] }, backup_reasons(home, "beta")]
  end

  def test_a_daily_backup_purges_the_backups_older_than_a_day
    home = fresh_home
    backup_at(home, MORNING - (30 * 3600))
    daily(home, MORNING)

    assert_equal [stamp(MORNING)], folder_names(home)
  end
end

# A home or a store folder with no store database takes no daily backup.
class GraphBackupDailyNothingTest < Plastic::TestCase
  include BackupHomes

  Daily = Plastic::Graph::Backup::Daily

  MORNING = Time.new(2026, 1, 2, 9, 0, 0, "+01:00")

  def daily(home, now, session_end: false) = Daily.new(home:, now:).then { |day| session_end ? day.end_session : day.begin_day }

  def test_a_store_folder_with_no_database_takes_none
    home = fresh_home
    FileUtils.mkdir_p(File.join(home, "stores", "empty"))

    assert_equal [[], []], [daily(home, MORNING), folder_names(home, "empty")]
  end

  def test_a_session_end_in_a_store_folder_with_no_database_takes_none
    home = fresh_home
    FileUtils.mkdir_p(File.join(home, "stores", "empty"))

    assert_equal [[], []], [daily(home, MORNING, session_end: true), folder_names(home, "empty")]
  end

  def test_a_home_with_no_stores_folder_takes_none
    assert_empty daily(Dir.mktmpdir, MORNING)
  end
end
