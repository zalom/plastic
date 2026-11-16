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

  def test_a_dry_run_takes_no_backup
    home = stale_home
    add_intent(home)
    clocked_call(home, "intent", "archive", "1", "--project", "alpha", "--dry-run")

    assert_equal [nil], backup_reasons(home)
  end
end
