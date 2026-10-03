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
  def test_removes_the_releases_and_the_launcher_plastic_owns
    installed_release
    result = call("uninstall", "--claude")

    assert_equal 0, result.code, result.err
    assert_equal [false, false], [File.exist?(share), File.symlink?(launcher)]
    assert_match(/removed:\s+#{Regexp.escape(share)}/, result.out)
  end

  def test_keeps_a_launcher_plastic_does_not_own
    installed_release
    File.delete(launcher)
    File.write(launcher, "#!/bin/sh\necho mine\n")
    result = call("uninstall", "--claude")

    assert_equal ["#!/bin/sh\necho mine\n", false], [File.read(launcher), File.exist?(share)]
    assert_includes result.out, "#{launcher} is not Plastic's launcher; it stays"
  end

  def test_keeps_the_releases_while_another_agent_stays_registered
    FileUtils.mkdir_p(File.join(@home, ".codex"))
    call("install", "--codex")
    installed_release
    call("uninstall", "--claude")

    assert_equal [true, true], [File.directory?(share), File.symlink?(launcher)]
  end

  def test_a_dry_run_names_the_releases_and_the_launcher
    installed_release
    result = call("uninstall", "--dry-run")

    assert_match(/remove:\s+#{Regexp.escape(share)}\n/, result.out)
    assert_match(/remove:\s+#{Regexp.escape(launcher)}\n/, result.out)
    assert_path_exists share
  end

  private

  def launcher = File.join(@home, ".local", "bin", "plastic")

  def installed_release
    activated("99.0.0")
    FileUtils.mkdir_p(File.dirname(launcher))
    File.symlink(File.join(share, "active", "bin", "plastic"), launcher)
  end
end
