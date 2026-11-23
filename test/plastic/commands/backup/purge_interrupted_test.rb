# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/backup/purge"

class BackupPurgeInterruptedTest < Plastic::TestCase
  include BackupHomes

  GOOD = [2026, 1, 1, 10, 0, 0].freeze
  STOPPED = "20260301100000"
  NOW = FixedClock::Clock.new(Time.utc(2026, 3, 1, 11, 0, 0))
  RUNNING = "20260301105900"

  def mark(home, name, status)
    folder = File.join(backups_dir(home), name)
    FileUtils.mkdir_p(folder)
    File.write(File.join(folder, "status.yml"), { "status" => status, "goal" => "full" }.to_yaml)
  end

  def seeded_home
    home = fresh_home
    backup_at(home, at(*GOOD))
    mark(home, "20260201100000", "failed")
    mark(home, STOPPED, "in-progress")
    mark(home, RUNNING, "in-progress")
    home
  end

  def bare(home, name) = FileUtils.mkdir_p(File.join(backups_dir(home), name))

  def test_interrupted_deletes_a_folder_with_no_status_file_older_than_five_minutes
    home = fresh_home
    bare(home, STOPPED)
    bare(home, RUNNING)

    assert_includes purge_call(home, "--store", "alpha", "--interrupted", clock: NOW).out, "purged: alpha/#{STOPPED}"
    assert_equal [RUNNING], folder_names(home)
  end

  def test_a_preview_lists_a_folder_with_no_status_file_and_deletes_nothing
    home = fresh_home
    bare(home, STOPPED)

    assert_includes purge_call(home, "--store", "alpha", "--interrupted", "--dry-run", clock: NOW).out, "preview: purge alpha/#{STOPPED}"
    assert_equal [STOPPED], folder_names(home)
  end

  def test_failed_leaves_a_folder_with_no_status_file
    home = fresh_home
    bare(home, STOPPED)
    purge_call(home, "--store", "alpha", "--failed", clock: NOW)

    assert_equal [STOPPED], folder_names(home)
  end

def test_interrupted_deletes_a_folder_with_an_empty_status_file
  home = fresh_home
  bare(home, STOPPED)
  File.write(File.join(backups_dir(home), STOPPED, "status.yml"), "")
  purge_call(home, "--store", "alpha", "--interrupted", clock: NOW)

  assert_empty folder_names(home)
end

def test_interrupted_deletes_a_folder_whose_status_file_has_no_status_key
  home = fresh_home
  bare(home, STOPPED)
  File.write(File.join(backups_dir(home), STOPPED, "status.yml"), { "goal" => "full" }.to_yaml)
  purge_call(home, "--store", "alpha", "--interrupted", clock: NOW)

  assert_empty folder_names(home)
end

def test_interrupted_keeps_a_folder_with_no_status_file_whose_name_is_not_a_real_time
  home = fresh_home
  bare(home, "20201399000000")
  result = purge_call(home, "--store", "alpha", "--interrupted", clock: NOW)

  assert_equal 0, result.code
  assert_equal ["20201399000000"], folder_names(home)
end

  def test_interrupted_deletes_only_the_in_progress_backup_older_than_five_minutes
    home = seeded_home

    assert_equal 0, purge_call(home, "--store", "alpha", "--interrupted", clock: NOW).code
    assert_equal %w[20260101100000 20260201100000].push(RUNNING), folder_names(home)
  end

  def test_interrupted_names_the_folder_it_deleted
    assert_includes purge_call(seeded_home, "--store", "alpha", "--interrupted", clock: NOW).out, "purged: alpha/#{STOPPED}"
  end

  def test_interrupted_never_deletes_a_backup_that_is_still_running
    home = fresh_home
    mark(home, RUNNING, "in-progress")

    assert_includes purge_call(home, "--store", "alpha", "--interrupted", clock: NOW).out, "purged: nothing"
    assert_equal [RUNNING], folder_names(home)
  end

  def test_a_preview_lists_the_interrupted_folder_and_deletes_nothing
    home = seeded_home
    result = purge_call(home, "--store", "alpha", "--interrupted", "--dry-run", clock: NOW)

    assert_includes result.out, "preview: purge alpha/#{STOPPED}"
    assert_equal 4, folder_names(home).size
  end

  def test_failed_still_leaves_the_interrupted_backup
    home = seeded_home
    purge_call(home, "--store", "alpha", "--failed", clock: NOW)

    assert_includes folder_names(home), STOPPED
  end

  def test_interrupted_with_all_refuses_and_deletes_nothing
    home = seeded_home

    assert_refused_with_usage purge_call(home, "--store", "alpha", "--interrupted", "--all", clock: NOW), "--interrupted"
    assert_equal 4, folder_names(home).size
  end

  def test_interrupted_with_failed_refuses_and_deletes_nothing
    home = seeded_home
    result = purge_call(home, "--store", "alpha", "--interrupted", "--failed", clock: NOW)

    assert_refused_with_usage result, "--interrupted"
    assert_equal 4, folder_names(home).size
  end

  def test_interrupted_with_older_than_refuses_and_deletes_nothing
    home = seeded_home
    result = purge_call(home, "--store", "alpha", "--interrupted", "--older-than", "2030-01-01", clock: NOW)

    assert_refused_with_usage result, "--interrupted"
    assert_equal 4, folder_names(home).size
  end

  def test_the_usage_line_and_summary_name_the_option
    summary = Plastic::CLI::TABLE.fetch("backup purge").last

    assert_includes summary, "--interrupted"
  end
end
