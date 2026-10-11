# frozen_string_literal: true

require "shellwords"
require_relative "commands/installer_helper"
require_relative "../test_helpers/backup_homes"

class DryRunNextTest < Plastic::TestCase
  include InstallerHelper
  include BackupHomes

  PROJECT = %w[--project global].freeze

  def printed_words(result)
    line = result.out.lines(chomp: true).grep(/\Anext: /).fetch(0)
    words = Shellwords.split(line.delete_prefix("next: "))
    words - PROJECT
  end

  def assert_next_is_the_call(argv, result, env: {})
    assert_equal 0, result.code, result.err
    assert_equal ["plastic", *(argv - ["--dry-run"])].sort, printed_words(result).sort
    refute_includes printed_words(result), "--dry-run", env.to_s
  end

  def test_backup_keeps_its_databases_option
    home = fresh_home
    argv = ["backup", "--store", "alpha", "--databases", "work_graph", "--dry-run"]

    assert_next_is_the_call argv, call(*argv, env: env_for(home))
  end

  def test_backup_purge_keeps_its_filter
    home = fresh_home
    argv = ["backup", "purge", "--store", "alpha", "--older-than", "2026-01-01", "--dry-run"]

    assert_next_is_the_call argv, call(*argv, env: env_for(home))
  end

  def test_backup_restore_keeps_its_timestamp
    home = fresh_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0))
    argv = ["backup", "restore", "--store", "alpha", "--timestamp", "20260101100000", "--dry-run"]

    assert_next_is_the_call argv, call(*argv, env: env_for(home))
  end

  def test_install_keeps_its_reinstall_switch
    argv = ["install", "--reinstall", "--dry-run"]

    assert_next_is_the_call argv, call(*argv)
  end

  def test_update_keeps_its_channel
    installed("0.0.1")
    argv = ["update", "--channel", "stable", "--dry-run"]

    assert_next_is_the_call argv, call(*argv)
  end

  def test_rollback_keeps_the_call
    activated("2.0.2", "2.0.3")
    argv = ["rollback", "--dry-run"]

    assert_next_is_the_call argv, call(*argv)
  end

  def test_uninstall_keeps_its_scope_switch
    claude_folder
    call("install", "--claude")
    argv = ["uninstall", "--all", "--dry-run"]

    assert_next_is_the_call argv, call(*argv)
  end

  def test_sync_up_keeps_the_call
    argv = ["sync", "up", "--dry-run"]

    assert_next_is_the_call argv, call(*argv)
  end

  def test_sync_down_keeps_the_call
    argv = ["sync", "down", "--dry-run"]

    assert_next_is_the_call argv, call(*argv)
  end

  def test_intent_revise_offers_the_call_without_the_dry_run
    call("intent", "new", "Alpha")
    argv = ["intent", "revise", "1", "Beta", "--dry-run"]

    assert_next_is_the_call argv, call(*argv)
  end
end
