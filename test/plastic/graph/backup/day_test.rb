# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/backup/day"

# The two backups of one store on one day. A start-of-day backup that failed
# counts as tried for the rest of that day, and a failed copy leaves no
# folder behind.
class GraphBackupDayTest < Plastic::TestCase
  include BackupHomes
  include BackupTriggers

  Backup = Plastic::Graph::Backup

  MORNING = Time.new(2026, 1, 2, 9, 0, 0, "+01:00")
  NOON = Time.new(2026, 1, 2, 12, 0, 0, "+01:00")
  NEXT_MORNING = Time.new(2026, 1, 3, 9, 0, 0, "+01:00")

  def root(home) = File.join(home, "stores", "alpha")

  def day(home, now, copy: Backup::Copy.new(now:)) = Backup::Day.new(root(home), "alpha", now:, copy:)

  def failing_copy(now) = Backup::Copy.new(now:, copier: ->(_source, _target) { raise IOError, "disk full" })

  def damage(home)
    Plastic::Graph::Database::ConnectionPool.release(root(home))
    File.write(store_file(home, "work_graph"), "not a database")
  end

  def test_a_failed_copy_leaves_no_backup_folder
    home = fresh_home

    assert_raises(IOError) { day(home, MORNING, copy: failing_copy(MORNING)).begin_day }
    assert_empty folder_names(home)
  end

  def test_a_store_whose_start_of_day_backup_failed_is_not_tried_again_that_day
    home = fresh_home
    damage(home)
    assert_raises(Backup::Writer::Error) { day(home, MORNING).begin_day }

    assert_nil day(home, NOON).begin_day
  end

  def test_a_failed_start_of_day_backup_of_the_day_before_does_not_count_for_today
    home = fresh_home
    damage(home)
    assert_raises(Backup::Writer::Error) { day(home, MORNING).begin_day }

    assert_raises(Backup::Writer::Error) { day(home, NEXT_MORNING).begin_day }
  end

  def test_a_session_end_after_a_failed_start_of_day_backup_tries_the_end_of_day_backup
    home = fresh_home
    assert_raises(IOError) { day(home, MORNING, copy: failing_copy(MORNING)).begin_day }
    day(home, NOON).end_session

    assert_equal ["end of day"], backup_reasons(home)
  end
end
