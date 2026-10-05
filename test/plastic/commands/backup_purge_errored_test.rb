# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/backup_purge"

class BackupPurgeErroredTest < Plastic::TestCase
  include BackupHomes

  GOOD = [2026, 1, 1, 10, 0, 0].freeze
  FAILED = "20260201100000"
  RUNNING = "20260301100000"

  def seeded_home
    home = fresh_home
    backup_at(home, at(*GOOD))
    mark(home, FAILED, "error")
    mark(home, RUNNING, "in-progress")
    home
  end

  def mark(home, name, status)
    folder = File.join(backups_dir(home), name)
    FileUtils.mkdir_p(folder)
    File.write(File.join(folder, "status.yml"), {"status" => status, "goal" => "full"}.to_yaml)
  end

  def test_errored_deletes_only_the_folders_marked_error
    home = seeded_home

    assert_equal 0, purge_call(home, "--store", "alpha", "--errored").code
    assert_equal ["20260101100000", RUNNING], folder_names(home)
  end

  def test_errored_keeps_the_rows_of_done_backups
    home = seeded_home
    purge_call(home, "--store", "alpha", "--errored")

    assert_equal ["alpha/20260101100000"], row_names(home)
  end

  def test_errored_names_each_folder_it_deleted
    out = purge_call(seeded_home, "--store", "alpha", "--errored").out

    assert_includes out, "purged: alpha/#{FAILED}"
  end

  def test_errored_with_no_errored_backup_says_nothing_was_purged
    home = fresh_home
    backup_at(home, at(*GOOD))

    assert_includes purge_call(home, "--store", "alpha", "--errored").out, "purged: nothing"
  end

  def test_a_preview_lists_the_errored_folders_and_deletes_nothing
    home = seeded_home
    result = purge_call(home, "--store", "alpha", "--errored", "--dry-run")

    assert_includes result.out, "preview: purge alpha/#{FAILED}"
    assert_equal 3, folder_names(home).size
  end

  def test_errored_with_all_refuses_and_deletes_nothing
    home = seeded_home

    assert_refused_with_usage purge_call(home, "--store", "alpha", "--errored", "--all"), "--errored"
    assert_equal 3, folder_names(home).size
  end

  def test_errored_with_older_than_refuses_and_deletes_nothing
    home = seeded_home

    assert_refused_with_usage purge_call(home, "--store", "alpha", "--errored", "--older-than", "2030-01-01"), "--errored"
    assert_equal 3, folder_names(home).size
  end

  def test_all_still_deletes_errored_and_running_folders
    home = seeded_home
    purge_call(home, "--store", "alpha", "--all")

    assert_empty folder_names(home)
  end
end
