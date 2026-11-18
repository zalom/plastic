# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/backup/purge"

class BackupPurgeLinesTest < Plastic::TestCase
  include BackupHomes

  def one_backup_home
    home = fresh_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0))
    home
  end

  def test_purging_all_prints_the_purged_folder_and_offers_the_list
    home = one_backup_home
    name = folder_names(home).first

    assert_case purge_call(home, "--store", "alpha", "--all"), code: 0,
      out: ["purged: alpha/#{name}", "next: plastic backup list --store alpha"]
    assert_empty folder_names(home)
  end

  def test_purging_all_as_a_preview_names_the_folder_and_keeps_it
    home = one_backup_home
    name = folder_names(home).first

    assert_case purge_call(home, "--store", "alpha", "--all", "--dry-run"), code: 0,
      out: ["preview: purge alpha/#{name}", "preview: the original store was not changed", "next: plastic backup purge --store alpha --all"]
    assert_equal [name], folder_names(home)
  end

  def test_purging_older_than_a_past_date_purges_nothing_and_offers_the_list
    home = one_backup_home

    assert_case purge_call(home, "--store", "alpha", "--older-than", "2000-01-01"), code: 0,
      out: ["purged: nothing", "next: plastic backup list --store alpha"]
    assert_equal 1, folder_names(home).size
  end

  def test_purging_failed_backups_when_none_failed_purges_nothing_and_offers_the_list
    home = one_backup_home

    assert_case purge_call(home, "--store", "alpha", "--failed"), code: 0,
      out: ["purged: nothing", "next: plastic backup list --store alpha"]
    assert_equal 1, folder_names(home).size
  end
end

class BackupPurgeTest < Plastic::TestCase
  include BackupHomes

  TIMES = [[2026, 1, 1, 10, 0, 0], [2026, 2, 28, 23, 59, 59], [2026, 3, 1, 0, 0, 0], [2026, 3, 5, 8, 0, 0]].freeze

  def stamps = TIMES.map { |parts| stamp(local_at(*parts)) }.sort

  def seeded_home
    home = fresh_home
    TIMES.each { |parts| backup_at(home, local_at(*parts)) }
    home
  end

  def assert_nothing_deleted(home, result, mention)
    assert_refused_with_usage result, mention
    assert_equal 4, folder_names(home).size
  end

  def test_a_purge_keeps_the_run_of_the_call_for_a_resume
    home = seeded_home
    purge_call(home, "--store", "alpha", "--all")

    assert_includes kept_run_tools(home), "backup purge"
  end

  def test_purging_the_global_store_removes_its_own_folders_and_leaves_the_others
    home = fresh_home
    seed_store(home, "global")
    backup_at(home, at(2026, 1, 1, 10, 0, 0), slug: "global")
    backup_at(home, at(2026, 1, 1, 10, 0, 0))

    assert_equal 0, purge_call(home, "--store", "global", "--all").code
    assert_equal [[], 1], [folder_names(home, "global"), folder_names(home).size]
  end

  def test_purging_all_when_there_are_no_backups_says_nothing_was_purged
    result = purge_call(fresh_home, "--store", "alpha", "--all")

    assert_equal [0, true], [result.code, result.out.include?("purged: nothing")]
  end

  def test_a_call_without_store_refuses_with_the_usage_line
    assert_refused_with_usage purge_call(fresh_home, "--all"), "--store"
  end

  def test_an_unregistered_store_refuses_and_names_it
    assert_refused_with_usage purge_call(fresh_home, "--store", "nowhere", "--all"), "nowhere"
  end

  def test_purge_with_neither_flag_refuses_and_deletes_nothing
    home = seeded_home

    assert_nothing_deleted home, purge_call(home, "--store", "alpha"), "--older-than"
  end

  def test_purge_with_both_flags_refuses_and_deletes_nothing
    home = seeded_home

    assert_nothing_deleted home, purge_call(home, "--store", "alpha", "--all", "--older-than", "2026-03-01"), "--all"
  end

  def test_older_than_deletes_only_backups_before_local_midnight_of_the_date_in_utc
    home = seeded_home

    assert_equal 0, purge_call(home, "--store", "alpha", "--older-than", "2026-03-01").code
    assert_equal stamps.last(2), folder_names(home)
  end

  def test_older_than_reads_a_full_time_with_its_offset
    home = seeded_home
    purge_call(home, "--store", "alpha", "--older-than", local_at(2026, 3, 5, 8, 0, 0).strftime("%Y-%m-%dT%H:%M:%S%:z"))

    assert_equal stamps.last(1), folder_names(home)
  end

  def test_an_unreadable_date_refuses_and_names_it
    home = seeded_home

    assert_nothing_deleted home, purge_call(home, "--store", "alpha", "--older-than", "last week"), "last week"
  end

  def test_a_day_that_does_not_exist_refuses_and_names_it
    home = seeded_home

    assert_nothing_deleted home, purge_call(home, "--store", "alpha", "--older-than", "2026-02-30"), "2026-02-30"
  end

  def test_all_deletes_only_the_named_stores_backups
    home = seeded_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0), slug: "beta")
    purge_call(home, "--store", "alpha", "--all")

    assert_equal %w[20260101100000], folder_names(home, "beta")
  end

  def test_a_preview_lists_the_folders_and_deletes_nothing
    home = seeded_home
    result = purge_call(home, "--store", "alpha", "--all", "--dry-run")

    assert_call result, code: 0, out: ["preview", stamps.first, stamps.last]
    assert_equal 4, folder_names(home).size
  end
end

class BackupPurgeHelpTest < Plastic::TestCase
  def help_lines
    environment = Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => @plastic_home }, input: StringIO.new,
      out: StringIO.new, err: StringIO.new, home: @home, directory: @home)
    Plastic::CLI.bin_call(%w[help backup purge], environment:, table: Plastic::CLI::TABLE)
    environment.out.string.lines.map(&:chomp)
  end

  def test_the_usage_line_says_one_of_the_three_filters_is_required
    assert_equal "plastic backup purge --store SLUG (--older-than DATE | --all | --failed) [--dry-run]", help_lines.first
  end

  def test_the_help_line_says_one_filter_is_required
    summary = Plastic::CLI::TABLE.fetch("backup purge").last

    assert_includes summary, "one of --all, --failed or --older-than"
  end
end

class BackupPurgeFailedTest < Plastic::TestCase
  include BackupHomes

  GOOD = [2026, 1, 1, 10, 0, 0].freeze
  FAILED = "20260201100000"
  RUNNING = "20260301100000"

  def seeded_home
    home = fresh_home
    backup_at(home, at(*GOOD))
    mark(home, FAILED, "failed")
    mark(home, RUNNING, "in-progress")
    home
  end

  def mark(home, name, status)
    folder = File.join(backups_dir(home), name)
    FileUtils.mkdir_p(folder)
    File.write(File.join(folder, "status.yml"), { "status" => status, "goal" => "full" }.to_yaml)
  end

  def test_failed_deletes_only_the_folders_marked_error
    home = seeded_home

    assert_equal 0, purge_call(home, "--store", "alpha", "--failed").code
    assert_equal ["20260101100000", RUNNING], folder_names(home)
  end

  def test_failed_names_each_folder_it_deleted
    out = purge_call(seeded_home, "--store", "alpha", "--failed").out

    assert_includes out, "purged: alpha/#{FAILED}"
  end

  def test_failed_with_no_errored_backup_says_nothing_was_purged
    home = fresh_home
    backup_at(home, at(*GOOD))

    assert_includes purge_call(home, "--store", "alpha", "--failed").out, "purged: nothing"
  end

  def test_a_preview_lists_the_errored_folders_and_deletes_nothing
    home = seeded_home
    result = purge_call(home, "--store", "alpha", "--failed", "--dry-run")

    assert_includes result.out, "preview: purge alpha/#{FAILED}"
    assert_equal 3, folder_names(home).size
  end

  def test_failed_with_all_refuses_and_deletes_nothing
    home = seeded_home

    assert_refused_with_usage purge_call(home, "--store", "alpha", "--failed", "--all"), "--failed"
    assert_equal 3, folder_names(home).size
  end

  def test_failed_with_older_than_refuses_and_deletes_nothing
    home = seeded_home

    assert_refused_with_usage purge_call(home, "--store", "alpha", "--failed", "--older-than", "2030-01-01"), "--failed"
    assert_equal 3, folder_names(home).size
  end

  def test_all_still_deletes_errored_and_running_folders
    home = seeded_home
    purge_call(home, "--store", "alpha", "--all")

    assert_empty folder_names(home)
  end
end
