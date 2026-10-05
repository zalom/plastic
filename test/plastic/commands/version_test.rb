# frozen_string_literal: true

require_relative "installer_helper"

class VersionCommandTest < Plastic::TestCase
  include InstallerHelper

  def test_reports_the_running_package_version_and_its_channel
    result = call("version", env: { "PLASTIC_PACKAGE_ROOT" => fake_package("9.1.0-alpha.2") })

    assert_equal 0, result.code
    assert_match(/version:\s+9\.1\.0-alpha\.2/, result.out)
    assert_match(/channel:\s+alpha/, result.out)
  end

  def test_a_version_file_wins_over_the_package_manifest
    root = fake_package("9.1.0")
    File.write(File.join(root, "VERSION"), "9.2.0-beta.1\n")
    result = call("version", "--json", env: { "PLASTIC_PACKAGE_ROOT" => root })

    assert_equal "9.2.0-beta.1", JSON.parse(result.out).fetch("result").fetch("version")
  end

  def test_fails_when_the_package_has_no_version_file
    root = FileUtils.mkdir_p(File.join(@home, "empty")).first
    result = call("version", env: { "PLASTIC_PACKAGE_ROOT" => root })

    assert_equal 1, result.code
    assert_includes result.err, "no VERSION file and no package.json"
  end

  def test_reading_the_version_writes_nothing_under_the_home
    before = tree_snapshot(@plastic_home)
    call("version")

    assert_equal before, tree_snapshot(@plastic_home)
  end

  def test_the_installer_commands_ship_with_the_core_files
    require_relative "../../../scripts/lib/installer_core"
    files = InstallerCore.new(package_root: PACKAGE_ROOT).send(:core_files)

    %w[version install update rollback uninstall].each do |name|
      assert Plastic::CLI.find([name]), "plastic #{name} is missing from the command table"
      assert_includes files, "scripts/lib/plastic/commands/#{name}.rb"
    end
  end

  def test_reports_a_healthy_installation_and_changes_nothing
    healthy_installation
    before = tree_snapshot(@home)
    result = call("version", env: { "PATH" => bin_dir })

    assert_equal 0, result.code, result.err
    assert_empty unmatched(result.out, healthy_rows), result.out
    assert_equal [before, false], [tree_snapshot(@home), result.out.include?("repair:")]
  end

  def test_names_the_repairs_after_the_checks
    damaged_installation
    out = call("version").out

    assert_operator out.index("repair:"), :>, out.index("installer lock:"), out
  end

  def test_names_a_repair_for_each_damaged_part_and_changes_nothing
    damaged_installation
    before = tree_snapshot(@home)
    result = call("version", env: { "PATH" => File.join(@home, "nowhere") })

    assert_empty unmatched(result.out, damaged_rows), result.out
    assert_equal [before, 4], [tree_snapshot(@home), result.out.scan("repair:").size]
  end

  def test_a_damaged_installation_exits_1_and_names_no_next_command
    damaged_installation
    result = call("version")

    assert_equal 1, result.code
    assert_includes result.err, "a part of the installation is broken; run the repairs named above, then check again"
    refute_match(/next:/, result.out)
  end

  def test_says_when_no_release_is_activated
    result = call("version")

    assert_match(/active:\s+none/, result.out)
    refute_match(/sqlite3 bundle:/, result.out)
  end

  def test_a_run_with_no_active_release_says_so_and_is_not_reported_whole
    result = call("version")

    assert_equal [0, ""], [result.code, result.err]
    assert_empty unmatched(result.out, [/installation:\s+no release is installed; this plastic runs outside a release/,
      /because:\s+no release is installed, so only Ruby was checked/]), result.out
    refute_includes result.out, "whole"
  end

  def test_version_reports_no_hooks_after_an_uninstall_that_names_no_agent
    activated("99.0.0-alpha.1")
    FileUtils.mkdir_p(File.join(@home, ".codex"))
    claude_folder
    call("install", "--claude", "--codex")
    call("uninstall")
    result = call("version")

    refute_match(/hooks:\s+point/, result.out)
  end

  def unmatched(out, patterns) = patterns.reject { |pattern| pattern.match?(out) }

  def healthy_rows
    [/active:\s+99\.0\.0-alpha\.2/, /previous:\s+99\.0\.0-alpha\.1/, /launcher:\s+#{Regexp.escape(File.join(bin_dir, "plastic"))}/,
      /ruby:\s+#{Regexp.escape(RUBY_VERSION)}/, /sqlite3 bundle:\s+present/, /hooks:\s+point at the active release/,
      /installer lock:\s+free/, /next:\s+plastic status/]
  end

  def damaged_rows
    [/launcher:\s+not on PATH/, /sqlite3 bundle:\s+missing/, /hooks:\s+point at #{Regexp.escape(@plastic_home)}/,
      /installer lock:\s+an activation was interrupted/]
  end

  def healthy_installation
    activated("99.0.0-alpha.1", "99.0.0-alpha.2")
    setup = File.join(share, "active", "runtime", "bundle", "bundler", "setup.rb")
    FileUtils.mkdir_p(File.dirname(setup))
    File.write(setup, "")
    FileUtils.mkdir_p(bin_dir)
    File.symlink(File.join(share, "active", "bin", "plastic"), File.join(bin_dir, "plastic"))
    hooks_pointing_at(File.join(share, "active", "bin", "plastic"))
  end

  def damaged_installation
    activated("99.0.0-alpha.1")
    hooks_pointing_at(File.join(@plastic_home, "bin", "plastic"))
    FileUtils.mkdir_p(File.join(share, "activation"))
  end

  def hooks_pointing_at(launcher)
    command = { "type" => "command", "command" => "env -u RUBYOPT \"#{launcher}\" hook resume --harness claude-code || true" }
    File.write(File.join(claude_folder, "settings.json"), JSON.generate("hooks" => { "SessionStart" => [{ "matcher" => "", "hooks" => [command] }] }))
  end

  def bin_dir = File.join(@home, ".local", "bin")
end
