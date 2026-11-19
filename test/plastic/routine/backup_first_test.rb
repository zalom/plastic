# frozen_string_literal: true

require_relative "../../test_helper"

# Every call that changes or replaces a store takes a backup first when the
# newest one is older than twelve hours. The calls need not succeed: the
# backup is taken before the work starts.
class RoutineBackupFirstTest < Plastic::TestCase
  include BackupHomes
  include BackupTriggers

  def first_backup_reason(argv)
    home = stale_home
    add_intent(home)
    clocked_call(home, *argv)
    backup_reasons(home)
  end

  def test_intent_archive_takes_a_backup_first
    assert_equal [nil, "intent archive"], first_backup_reason(%w[intent archive 1 --project alpha])
  end

  def test_sync_up_takes_a_backup_first
    assert_equal [nil, "sync up"], first_backup_reason(%w[sync up --project alpha])
  end

  def test_sync_down_takes_a_backup_first
    assert_equal [nil, "sync down"], first_backup_reason(%w[sync down --project alpha])
  end

  def test_backup_restore_takes_a_backup_first
    assert_includes first_backup_reason(%w[backup restore --store alpha --latest]), "backup restore"
  end

  def test_intent_end_takes_a_backup_first
    assert_equal [nil, "intent end"], first_backup_reason(%w[intent end 1 --project alpha])
  end

  def test_a_call_inside_twelve_hours_of_the_newest_backup_takes_none
    home = stale_home
    add_intent(home)
    clocked_call(home, "sync", "up", "--project", "alpha", at: ELEVEN_HOURS_LATER)

    assert_equal [nil], backup_reasons(home)
  end

  def test_a_backup_that_fails_is_said_and_the_call_goes_on
    home = stale_home
    add_intent(home)
    Plastic::Graph::Database::ConnectionPool.release(File.join(home, "stores", "alpha"))
    File.write(store_file(home, "work_graph"), "not a database")
    result = clocked_call(home, "sync", "up", "--project", "alpha")

    assert_match(/^backup: alpha was not backed up \(.*work_graph\.db.*\); the call goes on$/, result.out + result.err)
  end

  def test_a_dry_run_takes_no_backup
    home = stale_home
    add_intent(home)
    clocked_call(home, "intent", "archive", "1", "--project", "alpha", "--dry-run")

    assert_equal [nil], backup_reasons(home)
  end
end

# The backup before a call that can lose data purges after 24 hours with
# backup.daily on, and after three days with it off.
class RoutineBackupFirstRetentionTest < Plastic::TestCase
  include BackupHomes
  include BackupTriggers
  include ConfigHomes

  def old_backup_kept?(daily:)
    home = retention_home(daily:)
    clocked_call(home, "sync", "up", "--project", "alpha", at: LUNCHTIME)
    folder_names(home).include?(stamp(OLD_BACKUP))
  end

  def test_with_the_switch_on_the_backup_first_purges_a_backup_older_than_24_hours
    refute old_backup_kept?(daily: true)
  end

  def test_with_the_switch_off_the_backup_first_keeps_a_backup_younger_than_three_days
    assert old_backup_kept?(daily: false)
  end
end
