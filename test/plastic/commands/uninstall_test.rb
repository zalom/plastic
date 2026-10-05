# frozen_string_literal: true

require_relative "installer_helper"

class UninstallCommandTest < Plastic::TestCase
  include InstallerHelper

  def setup
    super
    claude_folder
    call("install", "--claude")
  end

  def test_a_dry_run_lists_the_files_it_would_remove_and_changes_nothing
    before = tree_snapshot(@home)
    result = call("uninstall", "--dry-run")

    assert_match(%r{remove:\s+.*\.claude/}, result.out)
    assert_match(/keep:\s+.*\.plastic/, result.out)
    assert_equal before, tree_snapshot(@home)
  end

  def test_removes_the_agent_files_and_keeps_the_home
    result = call("uninstall", "--claude")

    assert_equal 0, result.code, result.err
    refute_path_exists File.join(@home, ".claude", "plastic", "manifest.json")
    assert_path_exists File.join(@plastic_home, "VERSION")
  end

  def test_removes_the_hook_entries_that_run_plastic
    FileUtils.mkdir_p(File.join(@home, ".codex"))
    call("install", "--codex")
    call("uninstall", "--all")

    left = [File.join(@home, ".claude", "settings.json"), File.join(@home, ".codex", "hooks.json")]
      .select { |path| File.file?(path) && File.read(path).match?(/hook (resume|record)/) }

    assert_empty left
  end
end
