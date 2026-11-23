# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/backup/purge"

class BackupPurgeInterruptedTest < Plastic::TestCase
  include BackupHomes

  GOOD = [2026, 1, 1, 10, 0, 0].freeze
  STOPPED = "20260301100000"

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
    mark(home, stamp(Time.now - 60), "in-progress")
    home
  end

  def test_interrupted_deletes_only_the_in_progress_backup_older_than_five_minutes
    home = seeded_home
    running = stamp(Time.now - 60)

    assert_equal 0, purge_call(home, "--store", "alpha", "--interrupted").code
    assert_equal %w[20260101100000 20260201100000].push(running), folder_names(home)
  end

  def test_interrupted_names_the_folder_it_deleted
    assert_includes purge_call(seeded_home, "--store", "alpha", "--interrupted").out, "purged: alpha/#{STOPPED}"
  end

  def test_interrupted_never_deletes_a_backup_that_is_still_running
    home = fresh_home
    running = stamp(Time.now - 60)
    mark(home, running, "in-progress")

    assert_includes purge_call(home, "--store", "alpha", "--interrupted").out, "purged: nothing"
    assert_equal [running], folder_names(home)
  end

  def test_a_preview_lists_the_interrupted_folder_and_deletes_nothing
    home = seeded_home
    result = purge_call(home, "--store", "alpha", "--interrupted", "--dry-run")

    assert_includes result.out, "preview: purge alpha/#{STOPPED}"
    assert_equal 4, folder_names(home).size
  end

  def test_failed_still_leaves_the_interrupted_backup
    home = seeded_home
    purge_call(home, "--store", "alpha", "--failed")

    assert_includes folder_names(home), STOPPED
  end

  def test_interrupted_with_all_refuses_and_deletes_nothing
    home = seeded_home

    assert_refused_with_usage purge_call(home, "--store", "alpha", "--interrupted", "--all"), "--interrupted"
    assert_equal 4, folder_names(home).size
  end

  def test_the_usage_line_and_summary_name_the_option
    summary = Plastic::CLI::TABLE.fetch("backup purge").last

    assert_includes summary, "--interrupted"
  end
end
