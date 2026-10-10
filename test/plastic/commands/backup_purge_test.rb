# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/backup_purge"

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
    assert_equal stamps.last(2).map { |name| "alpha/#{name}" }, row_names(home)
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

  def test_a_folder_with_no_row_is_deleted
    home = seeded_home
    Plastic::Graph.create(home:, store: "alpha").databases.fetch(:local).transaction { |batch| batch.remove(:backups, name: "alpha/#{stamps.first}") }
    purge_call(home, "--store", "alpha", "--all")

    assert_empty folder_names(home)
  end

  def test_a_row_whose_folder_is_gone_is_removed
    home = seeded_home
    FileUtils.rm_rf(File.join(backups_dir(home), stamps.first))
    purge_call(home, "--store", "alpha", "--all")

    assert_empty row_names(home)
  end

  def test_all_deletes_only_the_named_stores_backups
    home = seeded_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0), slug: "beta")
    purge_call(home, "--store", "alpha", "--all")

    assert_equal [%w[20260101100000], %w[beta/20260101100000]], [folder_names(home, "beta"), row_names(home, "beta")]
  end

  def test_a_row_of_another_store_is_neither_listed_nor_removed
    home = seeded_home
    backup_at(home, at(2025, 1, 1, 10, 0, 0), slug: "beta")
    purge_call(home, "--store", "alpha", "--older-than", "2030-01-01")

    assert_equal ["beta/20250101100000"], row_names(home, "beta")
  end

  def test_a_preview_lists_the_folders_and_deletes_nothing
    home = seeded_home
    result = purge_call(home, "--store", "alpha", "--all", "--dry-run")

    assert_call result, code: 0, out: ["preview", stamps.first, stamps.last]
    assert_equal [4, 4], [folder_names(home).size, row_names(home).size]
  end
end
