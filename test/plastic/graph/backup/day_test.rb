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

  EVENING = Time.new(2026, 1, 2, 18, 0, 0, "+01:00")

  # Another process takes the folder name of the moment between the free-name check and the claim, as a dangling link does.
  def occupy_folder_name(home, time) = File.symlink(File.join(Dir.mktmpdir, "gone"), File.join(backups_dir(home), stamp(time)))

  def test_a_session_end_whose_folder_was_taken_keeps_the_earlier_end_of_day_backup
    home = fresh_home
    day(home, MORNING).begin_day
    day(home, NOON).end_session
    add_intent(home)
    occupy_folder_name(home, EVENING)
    day(home, EVENING).end_session

    assert_equal [stamp(MORNING), stamp(NOON)], Backup::Folders.new(root(home)).names
  end

  def test_a_session_end_after_a_failed_start_of_day_backup_tries_the_end_of_day_backup
    home = fresh_home
    assert_raises(IOError) { day(home, MORNING, copy: failing_copy(MORNING)).begin_day }
    day(home, NOON).end_session

    assert_equal ["end of day"], backup_reasons(home)
  end

  AFTER_MIDNIGHT = Time.new(2026, 1, 2, 0, 30, 0, "+01:00")

  # Rewrites a folder's status file without taken_at, as a backup written before it was recorded.
  def drop_taken_at(home, name)
    path = File.join(backups_dir(home), name, "status.yml")
    File.write(path, YAML.safe_load_file(path).except("taken_at").to_yaml)
  end

  def test_a_start_of_day_backup_with_no_recorded_time_reads_its_day_in_the_clock_s_offset
    home = fresh_home
    day(home, AFTER_MIDNIGHT).begin_day
    drop_taken_at(home, stamp(AFTER_MIDNIGHT))
    day(home, MORNING).begin_day

    assert_equal ["start of day"], backup_reasons(home)
  end
end

# The days the clocks change, read with the clock that Time.now gives under
# TZ=Europe/Berlin: +01:00 in winter and +02:00 in summer. A backup's day is
# the day of the clock when it was taken.
class GraphBackupDayClockChangeTest < Plastic::TestCase
  include BackupHomes
  include BackupTriggers

  Backup = Plastic::Graph::Backup

  # The summer time of Europe/Berlin in 2026, in UTC.
  BERLIN_SUMMER = (Time.utc(2026, 3, 29, 1)...Time.utc(2026, 10, 25, 1))

  # The day before the clocks go forward and that day: a start, a late session end, a start, and a session end.
  SPRING_DAYS = [[:begin_day, [2026, 3, 28, 9, 0]], [:end_session, [2026, 3, 28, 23, 30]], [:begin_day, [2026, 3, 29, 10, 0]], [:end_session, [2026, 3, 29, 18, 0]]].freeze

  # A wall-clock time in Europe/Berlin, with the offset that applied then; the hour the clocks go back reads as summer.
  def berlin(*day, hour, minute)
    summer = Time.new(*day, hour, minute, 0, "+02:00")
    BERLIN_SUMMER.cover?(summer) ? summer : Time.new(*day, hour, minute, 0, "+01:00")
  end

  # Runs each moment in turn on store alpha, given as [method, Berlin time], and adds an intent before the last one.
  def run_day(home, *moments)
    *before, (last_moment, last_time) = moments
    before.each { |moment, time| day(home, berlin(*time)).public_send(moment) }
    add_intent(home)
    day(home, berlin(*last_time)).public_send(last_moment)
  end

  def day(home, now) = Backup::Day.new(File.join(home, "stores", "alpha"), "alpha", now:)

  def test_a_start_of_day_backup_taken_late_the_night_before_the_clocks_go_forward_does_not_count_for_that_day
    home = fresh_home
    day(home, berlin(2026, 3, 28, 23, 30)).begin_day
    day(home, berlin(2026, 3, 29, 10, 0)).begin_day

    assert_equal ["start of day", "start of day"], backup_reasons(home)
  end

  def test_an_end_of_day_backup_of_the_night_before_the_clocks_go_forward_is_not_replaced_as_that_day_s
    home = fresh_home
    run_day(home, *SPRING_DAYS)

    assert_includes folder_names(home), stamp(berlin(2026, 3, 28, 23, 30))
  end

  def test_a_start_of_day_backup_taken_before_the_clocks_go_back_counts_for_that_day
    home = fresh_home
    day(home, berlin(2026, 10, 25, 0, 30)).begin_day
    day(home, berlin(2026, 10, 25, 10, 0)).begin_day

    assert_equal ["start of day"], backup_reasons(home)
  end

  def test_the_session_end_of_the_25_hour_day_keeps_that_day_s_start_of_day_backup
    home = fresh_home
    day(home, berlin(2026, 10, 25, 0, 10)).begin_day
    day(home, berlin(2026, 10, 25, 23, 30)).end_session

    assert_equal ["start of day", "end of day"], backup_reasons(home)
  end
end
