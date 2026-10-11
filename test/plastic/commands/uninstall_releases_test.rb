# frozen_string_literal: true

require_relative "installer_helper"
require_relative "../../../scripts/lib/plastic/installations"

class UninstallReleasesCommandTest < Plastic::TestCase
  include InstallerHelper

  def setup
    super
    recorded("claude-code", ".claude")
  end

  def test_removes_the_releases_and_the_launcher_plastic_owns
    installed_release
    result = call("uninstall", "1")

    assert_equal 0, result.code, result.err
    assert_equal [false, false], [File.exist?(share), File.symlink?(launcher)]
    assert_match(/removed:\s+#{Regexp.escape(share)}/, result.out)
  end

  def test_keeps_a_launcher_plastic_does_not_own
    installed_release
    File.delete(launcher)
    File.write(launcher, "#!/bin/sh\necho mine\n")
    result = call("uninstall", "1")

    assert_equal ["#!/bin/sh\necho mine\n", false], [File.read(launcher), File.exist?(share)]
    assert_includes result.out, "#{launcher} is not Plastic's launcher; it stays"
  end

  def test_keeps_the_releases_while_another_harness_stays_recorded
    recorded("codex", ".codex")
    installed_release
    call("uninstall", "1")

    assert_equal [true, true], [File.directory?(share), File.symlink?(launcher)]
  end

  def test_a_dry_run_names_the_releases_and_the_launcher
    installed_release
    result = call("uninstall", "--dry-run", "1")

    assert_match(/remove:\s+#{Regexp.escape(share)}\n/, result.out)
    assert_match(/remove:\s+#{Regexp.escape(launcher)}\n/, result.out)
    assert_path_exists share
  end

  def test_a_dry_run_keeps_the_releases_while_another_harness_stays_recorded
    recorded("codex", ".codex")
    installed_release
    result = call("uninstall", "--dry-run", "1")

    assert_match(%r{remove:\s+.*\.claude/}, result.out)
    refute_match(/remove:\s+#{Regexp.escape(share)}\n/, result.out)
  end

  private

  def recorded(harness, folder)
    root = File.join(@home, folder)
    file = File.join(root, "plastic", "VERSION")
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, "2.0.5\n")
    Plastic::Installations.write(@plastic_home, Plastic::Installations::Record.new(harness:, version: "2.0.5", roots: [root],
      files: [file], folders: [], settings: File.join(root, "settings.json"), hooks: [], status_line: nil, permissions: [], sections: []))
  end

  def launcher = File.join(@home, ".local", "bin", "plastic")

  def installed_release
    activated("99.0.0")
    FileUtils.mkdir_p(File.dirname(launcher))
    File.symlink(File.join(share, "active", "bin", "plastic"), launcher)
  end
end
