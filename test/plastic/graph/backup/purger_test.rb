# frozen_string_literal: true

require_relative "../../../test_helper"

class GraphBackupPurgerTest < Plastic::TestCase
  include BackupHomes

  Purger = Plastic::Graph::Backup::Purger

  def test_a_folder_is_purged_whatever_its_status
    home = fresh_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0))
    Plastic::Graph::Backup::Folders.new(File.join(home, "stores", "alpha")).write_report("20260101100000", status: "failed", goal: "full")
    Purger.new(File.join(home, "stores", "alpha")).remove("20260101100000")

    assert_empty folder_names(home)
  end

  def test_a_sweep_keeps_the_expired_folders_it_is_told_to_keep
    home = fresh_home
    [at(2026, 1, 1, 10, 0, 0), at(2026, 1, 1, 11, 0, 0), at(2026, 1, 5, 10, 0, 0)].each { |time| backup_at(home, time) }
    Purger.new(File.join(home, "stores", "alpha")).sweep(now: at(2026, 1, 5, 10, 0, 0), keep: ["20260101100000"])

    assert_equal %w[20260101100000 20260105100000], folder_names(home)
  end

  def test_names_before_a_time_are_strictly_older
    home = fresh_home
    backup_at(home, at(2026, 2, 28, 23, 59, 59))
    backup_at(home, at(2026, 3, 1, 0, 0, 0))
    purger = Purger.new(File.join(home, "stores", "alpha"))

    assert_equal ["20260228235959"], purger.names(older_than: at(2026, 3, 1, 0, 0, 0))
  end
end

class GraphBackupPurgerExpiryTest < Plastic::TestCase
  include BackupHomes

  Backup = Plastic::Graph::Backup
  NOW = Time.utc(2026, 1, 10, 12, 0, 0)

  def purger(home) = Backup::Purger.new(File.join(home, "stores", "alpha"))

  def write(home, time, reason: nil) = Backup::Writer.new(File.join(home, "stores", "alpha"), "alpha", now: time, reason:).call

  def test_a_backup_older_than_three_days_expires_and_a_newer_one_stays
    home = fresh_home
    write(home, NOW - (4 * 86_400))
    write(home, NOW - (2 * 86_400))

    assert_equal ["20260106120000"], purger(home).expired(now: NOW)
  end

  def test_only_the_newest_migration_backup_is_kept_past_three_days
    home = fresh_home
    write(home, NOW - (6 * 86_400), reason: "migration")
    write(home, NOW - (5 * 86_400), reason: "migration")
    write(home, NOW - (4 * 86_400))

    assert_equal %w[20260104120000 20260106120000], purger(home).expired(now: NOW)
  end

  def daily(home) = Backup::Purger.new(File.join(home, "stores", "alpha"), retention: Backup::Purger::DAILY_RETENTION)

  def test_under_the_daily_retention_a_backup_older_than_a_day_expires_and_a_newer_one_stays
    home = fresh_home
    write(home, NOW - (25 * 3600))
    write(home, NOW - (23 * 3600))

    assert_equal ["20260109110000"], daily(home).expired(now: NOW)
  end

  def test_under_the_daily_retention_the_newest_migration_backup_is_kept
    home = fresh_home
    write(home, NOW - (2 * 86_400), reason: "migration")
    write(home, NOW - (26 * 3600))

    assert_equal ["20260109100000"], daily(home).expired(now: NOW)
  end

  def test_under_the_default_retention_a_backup_two_days_old_stays
    home = fresh_home
    write(home, NOW - (2 * 86_400))

    assert_empty purger(home).expired(now: NOW)
  end
end

class GraphBackupPurgerInterruptedTest < Plastic::TestCase
  include BackupHomes

  def test_interrupted_names_in_progress_folders_older_than_five_minutes_only
    home = fresh_home
    folders = Plastic::Graph::Backup::Folders.new(File.join(home, "stores", "alpha"))
    now = Time.utc(2026, 3, 1, 10, 10, 0)
    { "20260301100000" => "in-progress", "20260301100800" => "in-progress", "20260301095000" => "failed" }.each do |name, status|
      FileUtils.mkdir_p(folders.path(name))
      folders.write_report(name, status:, goal: "full")
    end

    assert_equal ["20260301100000"], Plastic::Graph::Backup::Purger.new(File.join(home, "stores", "alpha")).interrupted(now:)
  end
end
