# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/backup_list"

class BackupListTest < Plastic::TestCase
  include BackupHomes

  FIRST = [2026, 1, 1, 10, 0, 0].freeze
  SECOND = [2026, 3, 1, 9, 30, 0].freeze

  def test_a_call_without_store_refuses_with_the_usage_line
    assert_refused_with_usage list_call(fresh_home), "--store"
  end

  def test_an_unregistered_store_refuses_and_names_it
    assert_refused_with_usage list_call(fresh_home, "--store", "nowhere"), "nowhere"
  end

  def test_the_global_store_is_listed_from_its_own_folder
    home = fresh_home
    seed_store(home, "global")
    backup_at(home, at(*FIRST), slug: "global")

    assert_call list_call(home, "--store", "global"), code: 0, out: %w[20260101100000]
  end

  def test_the_list_shows_each_timestamp
    home = fresh_home
    backup_at(home, at(*FIRST))
    backup_at(home, at(*SECOND))
    result = list_call(home, "--store", "alpha")

    assert_call result, code: 0, out: %w[20260101100000 20260301093000]
  end

  def test_the_list_numbers_each_backup_from_one_and_shows_the_local_start_time
    home = fresh_home
    backup_at(home, at(*FIRST))
    backup_at(home, at(*SECOND))
    out = list_call(home, "--store", "alpha").out

    assert_match(/^1\s+20260101100000\s+#{at(*FIRST).localtime.strftime("%Y-%m-%d %H:%M:%S")}/, out)
    assert_match(/^2\s+20260301093000\s+#{at(*SECOND).localtime.strftime("%Y-%m-%d %H:%M:%S")}/, out)
  end

  def test_the_list_shows_the_status_and_the_goal_after_the_start_time
    home = fresh_home
    backup_at(home, at(*FIRST))
    backup_at(home, at(*SECOND), databases: %w[work_graph])
    out = list_call(home, "--store", "alpha").out

    assert_match(/^1\s+20260101100000\s+\S+ \S+\s+done\s+full/, out)
    assert_match(/^2\s+20260301093000\s+\S+ \S+\s+done\s+partial:work_graph\.db/, out)
  end

  def test_a_folder_without_a_status_file_shows_unknown
    home = fresh_home
    backup_at(home, at(*FIRST))
    File.delete(File.join(backups_dir(home), "20260101100000", "status.yml"))

    assert_match(/^1\s+20260101100000\s+\S+ \S+\s+unknown/, list_call(home, "--store", "alpha").out)
  end

  def test_a_changed_file_is_flagged_and_fails_the_call
    home = fresh_home
    backup_at(home, at(*FIRST))
    File.write(Dir.glob(File.join(backups_dir(home), "*", "work_graph-*.db")).first, "changed", mode: "a")
    result = list_call(home, "--store", "alpha")

    assert_equal 1, result.code
    assert_includes result.out, "(changed)"
  end

  def test_a_row_with_no_folder_is_flagged_missing
    home = fresh_home
    backup_at(home, at(*FIRST))
    FileUtils.rm_rf(File.join(backups_dir(home), "20260101100000"))
    result = list_call(home, "--store", "alpha")

    assert_equal 1, result.code
    assert_includes result.out, "(missing)"
  end

  def test_a_folder_with_no_row_is_listed_as_no_row_and_does_not_fail
    home = fresh_home
    backup_at(home, at(*FIRST))
    Plastic::Graph.create(home:, store: "alpha").databases.fetch(:local).transaction { |batch| batch.remove(:backups, name: "alpha/20260101100000") }
    result = list_call(home, "--store", "alpha")

    assert_call result, code: 0, out: ["20260101100000", "(no row)"]
  end

  def test_a_row_of_another_store_is_neither_listed_nor_removed
    home = fresh_home
    backup_at(home, at(*FIRST), slug: "beta")
    result = list_call(home, "--store", "alpha")

    refute_includes result.out, "20260101100000"
    assert_equal ["beta/20260101100000"], row_names(home, "beta")
  end
end
