# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/backup/day"

# The folders of one day, read by their name or by the time their status records.
class GraphBackupDayReaderTest < Plastic::TestCase
  include BackupHomes
  include BackupTriggers

  Backup = Plastic::Graph::Backup

  MORNING = Time.new(2026, 1, 2, 9, 0, 0, "+01:00")

  def test_a_folder_whose_name_is_not_a_real_time_and_has_no_taken_at_does_not_stop_the_start_of_day_backup
    home = fresh_home
    FileUtils.mkdir_p(File.join(backups_dir(home), "20261399000000"))

    refute_nil Backup::Day.new(File.join(home, "stores", "alpha"), "alpha", now: MORNING, zone: "+01:00").begin_day
    assert_includes folder_names(home), "20261399000000"
  end

  def test_a_second_session_end_of_an_unchanged_store_takes_no_second_end_of_day_backup
    home = fresh_home
    day = Backup::Day.new(File.join(home, "stores", "alpha"), "alpha", now: MORNING, zone: "+01:00")
    day.begin_day
    day.end_session
    day.end_session

    assert_equal ["start of day", "end of day"], backup_reasons(home)
  end
end
