# frozen_string_literal: true

require_relative "../../../test_helper"

class GraphBackupDueTest < Plastic::TestCase
  include BackupHomes
  include BackupTriggers

  Due = Plastic::Graph::Backup::Due

  def due(home, now, slug: "alpha") = Due.new(home:, slug:, now:)

  def test_a_store_with_no_backup_takes_one_and_records_why
    home = fresh_home

    due(home, SEEDED).call("session start")

    assert_equal ["session start"], backup_reasons(home)
  end

  def test_a_store_whose_newest_backup_is_older_than_twelve_hours_takes_one
    home = stale_home
    add_intent(home)

    due(home, THIRTEEN_HOURS_LATER).call("sync up")

    assert_equal [nil, "sync up"], backup_reasons(home)
  end

  def test_a_store_whose_newest_backup_is_twelve_hours_old_or_less_takes_none
    home = stale_home
    add_intent(home)

    due(home, ELEVEN_HOURS_LATER).call("sync up")

    assert_equal [nil], backup_reasons(home)
  end

  def test_a_store_that_did_not_change_takes_none_however_old_its_newest_backup
    home = stale_home

    due(home, THIRTEEN_HOURS_LATER).call("sync up")

    assert_equal [nil], backup_reasons(home)
  end

  def test_a_damaged_database_takes_no_backup_and_raises_nothing
    home = stale_home
    Plastic::Graph::Database::ConnectionPool.release(home)
    File.write(store_file(home, "work_graph"), "not a database")

    result = due(home, THIRTEEN_HOURS_LATER).call("sync up")

    assert_equal [:failed, [nil]], [result.status, backup_reasons(home)]
  end

  def test_a_store_folder_with_no_database_takes_none_and_reports_no_failure
    home = fresh_home
    FileUtils.mkdir_p(File.join(home, "stores", "empty"))

    result = due(home, SEEDED, slug: "empty").call("sync down")

    assert_equal [:missing, false], [result.status, File.directory?(File.join(home, "stores", "empty", "backups"))]
  end

  def test_a_store_that_does_not_exist_takes_none
    home = fresh_home

    assert_equal :missing, due(home, SEEDED, slug: "nowhere").call("session start").status
  end
end

# The purge of backups older than three days runs after an automatic backup is taken.
class GraphBackupDuePurgeTest < Plastic::TestCase
  include BackupHomes
  include BackupTriggers

  Due = Plastic::Graph::Backup::Due
  FOUR_DAYS_LATER = SEEDED + (4 * 24 * 3600)

  def migration_backup(home, now)
    add_intent(home)
    Plastic::Graph::Backup::Writer.new(File.join(home, "stores", "alpha"), "alpha", now:, reason: "migration").call
  end

  def back_up_after_four_days(home)
    add_intent(home)
    Due.new(home:, slug: "alpha", now: FOUR_DAYS_LATER).call("sync up")
  end

  def test_a_backup_taken_removes_the_folders_older_than_three_days_with_their_rows
    home = stale_home
    back_up_after_four_days(home)

    assert_equal [stamp(FOUR_DAYS_LATER)], folder_names(home)
  end

  def test_the_newest_migration_backup_stays_until_a_newer_one_is_taken
    home = stale_home
    migration_backup(home, SEEDED + 3600)
    back_up_after_four_days(home)

    assert_equal [stamp(SEEDED + 3600), stamp(FOUR_DAYS_LATER)], folder_names(home)
  end

  def test_a_store_that_took_no_backup_purges_nothing
    home = stale_home
    result = Due.new(home:, slug: "alpha", now: FOUR_DAYS_LATER).call("sync up")

    assert_equal [:unchanged, [stamp(SEEDED)]], [result.status, folder_names(home)]
  end

  def test_with_daily_backups_a_backup_taken_removes_the_folders_older_than_a_day
    home = stale_home
    add_intent(home)
    later = SEEDED + (25 * 3600)
    Due.new(home:, slug: "alpha", now: later, retention: Plastic::Graph::Backup::Purger::DAILY_RETENTION).call("sync up")

    assert_equal [stamp(later)], folder_names(home)
  end

  def test_a_newest_folder_whose_name_is_not_a_real_time_is_ignored_when_deciding_whether_a_backup_is_due
    home = stale_home
    add_intent(home)
    Dir.mkdir(File.join(backups_dir(home), "20261399000000"))

    result = Due.new(home:, slug: "alpha", now: THIRTEEN_HOURS_LATER).call("sync up")

    assert_equal [:taken, [nil, "sync up"]], [result.status, backup_reasons(home).first(2)]
  end
end
