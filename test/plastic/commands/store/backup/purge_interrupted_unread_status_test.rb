# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/commands/store/backup/purge"

class BackupPurgeInterruptedUnreadStatusTest < Plastic::TestCase
  include BackupHomes

  STOPPED = "20260301100000"
  NOW = FixedClock::Clock.new(Time.utc(2026, 3, 1, 11, 0, 0))
  RUNNING = "20260301105900"

  def bare(home, name) = FileUtils.mkdir_p(File.join(backups_dir(home), name))

  def test_interrupted_deletes_a_folder_with_no_status_file_older_than_five_minutes
    home = fresh_home
    bare(home, STOPPED)
    bare(home, RUNNING)

    assert_includes purge_call(home, "--project", "alpha", "--interrupted", clock: NOW).out, "purged: alpha/#{STOPPED}"
    assert_equal [RUNNING], folder_names(home)
  end

  def test_a_preview_lists_a_folder_with_no_status_file_and_deletes_nothing
    home = fresh_home
    bare(home, STOPPED)

    assert_includes purge_call(home, "--project", "alpha", "--interrupted", "--dry-run", clock: NOW).out, "preview: purge alpha/#{STOPPED}"
    assert_equal [STOPPED], folder_names(home)
  end

  def test_failed_leaves_a_folder_with_no_status_file
    home = fresh_home
    bare(home, STOPPED)
    purge_call(home, "--project", "alpha", "--failed", clock: NOW)

    assert_equal [STOPPED], folder_names(home)
  end

  def test_interrupted_deletes_a_folder_with_an_empty_status_file
    home = fresh_home
    bare(home, STOPPED)
    File.write(File.join(backups_dir(home), STOPPED, "status.yml"), "")
    purge_call(home, "--project", "alpha", "--interrupted", clock: NOW)

    assert_empty folder_names(home)
  end

  def test_interrupted_deletes_a_folder_whose_status_file_has_no_status_key
    home = fresh_home
    bare(home, STOPPED)
    File.write(File.join(backups_dir(home), STOPPED, "status.yml"), { "goal" => "full" }.to_yaml)
    purge_call(home, "--project", "alpha", "--interrupted", clock: NOW)

    assert_empty folder_names(home)
  end

  def test_interrupted_keeps_a_folder_with_no_status_file_whose_name_is_not_a_real_time
    home = fresh_home
    bare(home, "20201399000000")
    result = purge_call(home, "--project", "alpha", "--interrupted", clock: NOW)

    assert_equal 0, result.code
    assert_equal ["20201399000000"], folder_names(home)
  end
end
