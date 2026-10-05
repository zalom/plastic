# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/backup"
require_relative "../../../scripts/lib/plastic/commands/backup_restore"
require_relative "../../../scripts/lib/plastic/commands/backup_list"

class BackupLogTest < Plastic::TestCase
  include BackupHomes

  def log_in(home) = File.join(backups_dir(home), folder_names(home).first, "backup.log")

  def test_live_prints_the_log_lines_in_order
    home = fresh_home
    out = backup_call(home, "--store", "alpha", "--live").out
    lines = File.readlines(log_in(home), chomp: true)

    assert_equal lines, out.lines(chomp: true).first(lines.size)
  end

  def test_live_still_ends_with_the_backup_summary
    out = backup_call(fresh_home, "--store", "alpha", "--live").out

    assert_match(%r{^backup: alpha/\d{14}, 3 databases}, out)
  end

  def test_without_live_the_output_holds_no_log_line
    out = backup_call(fresh_home, "--store", "alpha").out

    refute_match(/result=/, out)
  end

  def test_a_backup_writes_the_log_in_its_folder_either_way
    home = fresh_home
    backup_call(home, "--store", "alpha")

    assert_path_exists log_in(home)
  end

  def test_restore_ignores_the_log
    home = fresh_home
    backup_call(home, "--store", "alpha")
    result = restore_call(home, "--store", "alpha", "--latest")

    assert_equal 0, result.code
    refute_includes result.out, "backup.log"
  end

  def test_list_ignores_the_log
    home = fresh_home
    backup_call(home, "--store", "alpha")
    out = list_call(home, "--store", "alpha").out

    refute_includes out, "backup.log"
    assert_match(/^1\s+\d{14}/, out)
  end

  def test_purge_removes_the_log_with_its_folder
    home = fresh_home
    backup_call(home, "--store", "alpha")
    purge_call(home, "--store", "alpha", "--all")

    assert_empty folder_names(home)
  end
end
