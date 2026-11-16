# frozen_string_literal: true

require_relative "../../../test_helper"

class GraphBackupPurgerTest < Plastic::TestCase
  include BackupHomes

  Purger = Plastic::Graph::Backup::Purger

  def test_a_failed_row_delete_puts_the_folder_back
    home = fresh_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0))
    refusing = Object.new
    def refusing.transaction = raise(StandardError, "the row cannot be deleted")
    purger = Purger.new(refusing, File.join(home, "stores", "alpha"), "alpha")

    assert_raises(StandardError) { purger.remove("20260101100000") }
    assert_equal ["20260101100000"], folder_names(home)
    assert_equal 5, Dir.children(File.join(backups_dir(home), "20260101100000")).size
  end

  def test_a_failed_row_delete_with_no_folder_just_raises
    refusing = Object.new
    def refusing.transaction = raise(StandardError, "the row cannot be deleted")
    purger = Purger.new(refusing, File.join(fresh_home, "stores", "alpha"), "alpha")

    assert_raises(StandardError) { purger.remove("20260101100000") }
  end

  def test_a_folder_is_purged_whatever_its_status
    home = fresh_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0))
    Plastic::Graph::Backup::Folders.new(File.join(home, "stores", "alpha")).write_report("20260101100000", status: "failed", goal: "full")
    local_db = Plastic::Graph.create(home:, store: "alpha").databases.fetch(:local)
    Purger.new(local_db, File.join(home, "stores", "alpha"), "alpha").remove("20260101100000")

    assert_empty folder_names(home)
  end

  def test_names_before_a_time_are_strictly_older
    home = fresh_home
    backup_at(home, at(2026, 2, 28, 23, 59, 59))
    backup_at(home, at(2026, 3, 1, 0, 0, 0))
    purger = Purger.new(nil, File.join(home, "stores", "alpha"), "alpha")

    assert_equal ["20260228235959"], purger.names(older_than: at(2026, 3, 1, 0, 0, 0))
  end
end

class GraphBackupPurgerExpiryTest < Plastic::TestCase
  include BackupHomes

  Backup = Plastic::Graph::Backup
  NOW = Time.utc(2026, 1, 10, 12, 0, 0)

  def purger(home) = Backup::Purger.new(Plastic::Graph.create(home:, store: "alpha").databases.fetch(:local), File.join(home, "stores", "alpha"), "alpha")

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
end
