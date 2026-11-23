# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/backup/day"
require_relative "../../../support/child_process"
require "json"
require "rbconfig"

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

  # Every case reads its days at +01:00, Berlin in winter, whatever the zone of the machine that runs it.
  ZONE = "+01:00"

  def day(home, now, copy: Backup::Copy.new(now:)) = Backup::Day.new(root(home), "alpha", now:, copy:, zone: ZONE)

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

  def test_a_folder_whose_name_is_not_a_real_time_and_has_no_taken_at_does_not_stop_the_start_of_day_backup
    home = fresh_home
    FileUtils.mkdir_p(File.join(backups_dir(home), "20261399000000"))

    refute_nil day(home, MORNING).begin_day
    assert_includes folder_names(home), "20261399000000"
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
  def forget_backup_time(home, name)
    path = File.join(backups_dir(home), name, "status.yml")
    File.write(path, YAML.safe_load_file(path).except("taken_at").to_yaml)
  end

  # Rewrites a folder's taken_at in UTC, the form every stored time takes.
  def utc_backup_time(home, name)
    path = File.join(backups_dir(home), name, "status.yml")
    report = YAML.safe_load_file(path)
    File.write(path, report.merge("taken_at" => Time.iso8601(report.fetch("taken_at")).getutc.iso8601).to_yaml)
  end

  def test_a_start_of_day_backup_taken_just_after_midnight_and_recorded_in_utc_counts_for_that_local_day
    home = fresh_home
    day(home, AFTER_MIDNIGHT).begin_day
    utc_backup_time(home, stamp(AFTER_MIDNIGHT))
    day(home, MORNING).begin_day

    assert_equal ["start of day"], backup_reasons(home)
  end

  def test_a_failed_start_of_day_backup_just_after_midnight_recorded_in_utc_counts_for_that_local_day
    home = fresh_home
    damage(home)
    FileUtils.mkdir_p(backups_dir(home))
    File.write(File.join(backups_dir(home), Backup::Day::FAILED_START), { "at" => "2026-01-01T23:30:00Z" }.to_yaml)

    assert_nil day(home, MORNING).begin_day
  end

  def test_a_start_of_day_backup_with_no_recorded_time_reads_its_day_from_its_folder_name
    home = fresh_home
    day(home, AFTER_MIDNIGHT).begin_day
    forget_backup_time(home, stamp(AFTER_MIDNIGHT))
    day(home, MORNING).begin_day

    assert_equal ["start of day"], backup_reasons(home)
  end

  def write_failed_start(home, at)
    FileUtils.mkdir_p(backups_dir(home))
    File.write(File.join(backups_dir(home), Backup::Day::FAILED_START), "at: '#{at}'\n")
  end

  def test_a_failed_start_file_that_holds_an_impossible_time_is_reported_with_its_path
    home = fresh_home
    write_failed_start(home, "2026-01-02T25:00:00Z")
    error = assert_raises(Backup::Day::Unreadable) { day(home, MORNING).begin_day }

    assert_includes error.message, "#{Backup::Folders::NAME}/#{Backup::Day::FAILED_START} holds 2026-01-02T25:00:00Z"
  end

  def test_a_backup_whose_status_holds_an_impossible_time_is_reported_with_its_path
    home = fresh_home
    day(home, AFTER_MIDNIGHT).begin_day
    path = File.join(backups_dir(home), stamp(AFTER_MIDNIGHT), "status.yml")
    File.write(path, File.read(path).sub(/^taken_at: .*$/, "taken_at: '2026-01-02T25:00:00Z'"))
    error = assert_raises(Backup::Day::Unreadable) { day(home, MORNING).begin_day }

    assert_includes error.message, "#{Backup::Folders::NAME}/#{stamp(AFTER_MIDNIGHT)}/status.yml holds 2026-01-02T25:00:00Z"
  end
end

# The days the clocks change in Europe/Berlin: +01:00 in winter and +02:00 in
# summer. A backup's day is the day of the clock when it was taken. Each case
# runs in a child process with TZ=Europe/Berlin, the way a machine in Berlin
# runs Plastic, since a fixed offset knows no summer time.
class GraphBackupDayClockChangeTest < Minitest::Test
  ROOT = File.expand_path("../../../..", __dir__)

  # Runs each moment in turn on store alpha of a fresh home, given as [method, Berlin wall-clock time] or
  # ["add_intent"], and prints the reasons and the folder names of its backups.
  SCRIPT = <<~CHILD
    require "json"
    require "plastic/graph"
    require "plastic/graph/backup/day"
    require "test_helpers/backup_homes"
    require "test_helpers/backup_triggers"
    include BackupHomes
    include BackupTriggers
    home = fresh_home
    JSON.parse(ARGV.fetch(0)).each do |moment, time|
      next add_intent(home) if moment == "add_intent"

      Plastic::Graph::Backup::Day.new(File.join(home, "stores", "alpha"), "alpha", now: Time.new(*time)).public_send(moment)
    end
    puts JSON.generate(reasons: backup_reasons(home), folders: folder_names(home))
  CHILD

  # The day before the clocks go forward and that day: a start, a late session end, a start, a change, and a session end.
  SPRING_DAYS = [["begin_day", [2026, 3, 28, 9, 0]], ["end_session", [2026, 3, 28, 23, 30]], ["begin_day", [2026, 3, 29, 10, 0]], ["add_intent"],
    ["end_session", [2026, 3, 29, 18, 0]]].freeze

  def in_berlin(*moments)
    out, err, status = ChildProcess.capture3({ "TZ" => "Europe/Berlin", "TMPDIR" => Dir.tmpdir }, RbConfig.ruby, "-I", File.join(ROOT, "lib"), "-I", File.join(ROOT, "test"),
      "-e", SCRIPT, JSON.generate(moments))

    assert_predicate status, :success?, err
    JSON.parse(out)
  end

  def test_a_start_of_day_backup_taken_late_the_night_before_the_clocks_go_forward_does_not_count_for_that_day
    found = in_berlin(["begin_day", [2026, 3, 28, 23, 30]], ["begin_day", [2026, 3, 29, 10, 0]])

    assert_equal ["start of day", "start of day"], found.fetch("reasons")
  end

  def test_an_end_of_day_backup_of_the_night_before_the_clocks_go_forward_is_not_replaced_as_that_day_s
    night_before = Time.new(2026, 3, 28, 23, 30, 0, "+01:00").getutc.strftime("%Y%m%d%H%M%S")

    assert_includes in_berlin(*SPRING_DAYS).fetch("folders"), night_before
  end

  def test_a_start_of_day_backup_taken_before_the_clocks_go_back_counts_for_that_day
    found = in_berlin(["begin_day", [2026, 10, 25, 0, 30]], ["begin_day", [2026, 10, 25, 10, 0]])

    assert_equal ["start of day"], found.fetch("reasons")
  end

  def test_the_session_end_of_the_25_hour_day_keeps_that_day_s_start_of_day_backup
    found = in_berlin(["begin_day", [2026, 10, 25, 0, 10]], ["end_session", [2026, 10, 25, 23, 30]])

    assert_equal ["start of day", "end of day"], found.fetch("reasons")
  end
end
