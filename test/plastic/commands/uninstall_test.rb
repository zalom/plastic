# frozen_string_literal: true

require_relative "installer_helper"
require "minitest/autorun"
require "fileutils"
require "tmpdir"

class UninstallCommandTest < Plastic::TestCase
  include InstallerHelper

  def setup
    super
    written_record("claude-code", ".claude")
  end

  def test_with_no_terminal_the_recorded_harnesses_are_listed_picked
    FileUtils.mkdir_p(File.join(@home, ".codex"))
    result = call("uninstall")

    assert_equal [0, ""], [result.code, result.err]
    assert_match(/1  \[x\] claude-code\n.*2  \[ \] codex/m, result.out)
  end

  def test_with_no_terminal_the_next_step_asks_the_person_and_nothing_is_removed
    before = tree_snapshot(@home)
    result = call("uninstall", "--dry-run")

    assert_includes result.out, "next: plastic uninstall --dry-run <answer>"
    assert_equal before, tree_snapshot(@home)
  end

  def test_answering_q_removes_nothing
    before = tree_snapshot(@home)
    result = call("uninstall", "q")

    assert_equal [0, true], [result.code, result.out.include?("the person left with no change")]
    assert_equal before, tree_snapshot(@home)
  end

  def test_a_harness_with_no_record_is_named_and_left_alone
    FileUtils.mkdir_p(File.join(@home, ".codex"))
    before = tree_snapshot(@home)
    result = call("uninstall", "2")

    assert_equal [0, true], [result.code, result.out.include?("codex: no record lists what Plastic wrote")]
    assert_equal before, tree_snapshot(@home)
  end

  def test_a_harness_with_no_record_is_not_reported_removed_and_names_the_reinstall
    FileUtils.mkdir_p(File.join(@home, ".codex"))
    result = call("uninstall", "2")

    refute_includes result.out, "is removed from"
    assert_includes result.out, "next: plastic install --reinstall"
  end

  def test_with_no_harness_recorded_or_found_it_names_init
    FileUtils.rm_rf(File.join(@home, ".claude"))
    Plastic::Installations.delete(@plastic_home, "claude-code")
    result = call("uninstall", "1")

    assert_equal [0, ""], [result.code, result.err]
    assert_includes result.out, "next: plastic init"
  end
end

class UninstallPreviewCommandTest < Plastic::TestCase
  include InstallerHelper

  def setup
    super
    claude_folder
    call("init", "1")
  end

  def test_a_dry_run_lists_the_files_it_would_remove_and_changes_nothing
    before = tree_snapshot(@home)
    result = call("uninstall", "--dry-run", "1")

    assert_match(%r{remove:\s+.*\.claude/}, result.out)
    assert_match(/keep:\s+.*\.plastic/, result.out)
    assert_equal before, tree_snapshot(@home)
  end

  def test_the_preview_lists_every_path_the_uninstall_removes
    activated("2.0.0")
    paths = home_paths
    listed = call("uninstall", "--dry-run", "a").out.scan(/^(?:remove|change):\s+(\S+)/).flatten

    call("uninstall", "a")
    gone = paths.reject { |entry| File.exist?(entry) || File.symlink?(entry) }

    assert_empty gone.reject { |entry| listed.any? { |item| entry == item || entry.start_with?("#{item}/") } }
  end

  def home_paths = Dir.glob(File.join(@home, "**", "*"), File::FNM_DOTMATCH).reject { |entry| entry.end_with?("/.", "/..") }
end

class UninstallReleasesCommandTest < Plastic::TestCase
  include InstallerHelper

  def setup
    super
    written_record("claude-code", ".claude")
  end

  def test_removes_the_releases_and_the_launcher_plastic_owns
    installed_release
    result = call("uninstall", "1")

    assert_equal 0, result.code, result.err
    assert_equal [false, false], [File.exist?(share), File.symlink?(launcher)]
    assert_match(/removed:\s+#{Regexp.escape(share)}/, result.out)
  end

  def test_after_the_last_harness_the_next_line_names_no_command_the_run_removed
    installed_release
    result = call("uninstall", "1")

    refute_match(/^next:/, result.out)
    assert_match(/^because: .*install\.sh/, result.out)
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
    written_record("codex", ".codex")
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
    written_record("codex", ".codex")
    installed_release
    result = call("uninstall", "--dry-run", "1")

    assert_match(%r{remove:\s+.*\.claude/}, result.out)
    refute_match(/remove:\s+#{Regexp.escape(share)}\n/, result.out)
  end

  private

  def launcher = File.join(@home, ".local", "bin", "plastic")

  def installed_release
    activated("99.0.0")
    FileUtils.mkdir_p(File.dirname(launcher))
    File.symlink(File.join(share, "active", "bin", "plastic"), launcher)
  end
end

class UninstallRemovalCommandTest < Plastic::TestCase
  include InstallerHelper

  def setup
    super
    claude_folder
    call("init", "1")
  end

  def test_removes_the_harness_files_and_its_record_and_keeps_the_home
    result = call("uninstall", "1")

    assert_equal 0, result.code, result.err
    refute_path_exists File.join(@home, ".claude", "plastic")
    assert_equal [[], true], [Plastic::Installations.recorded(@plastic_home), File.exist?(File.join(@plastic_home, "VERSION"))]
  end

  def test_keeps_the_entries_the_person_wrote_in_the_settings_file
    path = File.join(@home, ".claude", "settings.json")
    settings = JSON.parse(File.read(path))
    settings["hooks"]["Stop"] << { "hooks" => [{ "type" => "command", "command" => "mine" }] }
    File.write(path, JSON.generate(settings.merge("model" => "opus", "permissions" => { "deny" => ["Read(./secret)"] })))
    call("uninstall", "1")

    assert_equal [{ "Stop" => [{ "hooks" => [{ "type" => "command", "command" => "mine" }] }] }, "opus", { "deny" => ["Read(./secret)"] }],
      JSON.parse(File.read(path)).values_at("hooks", "model", "permissions")
  end

  def test_removes_a_hermes_install_by_its_record
    FileUtils.mkdir_p(File.join(@home, ".hermes"))
    call("init", "2")
    result = call("uninstall", "2")

    assert_equal 0, result.code, result.err
    assert_equal [[], ["claude-code"]], [Dir.glob(File.join(@home, ".hermes", "**", "plastic*")), Plastic::Installations.recorded(@plastic_home)]
  end

  def test_removes_the_hook_entries_that_run_plastic
    FileUtils.mkdir_p(File.join(@home, ".codex"))
    call("init", "2")
    call("uninstall", "a")

    left = [File.join(@home, ".claude", "settings.json"), File.join(@home, ".codex", "hooks.json")]
      .select { |path| File.file?(path) && File.read(path).match?(/hook (resume|record)/) }

    assert_empty left
  end
end

class UninstallSettingsCommandTest < Plastic::TestCase
  include InstallerHelper

  def setup
    super
    claude_folder
    call("init", "1")
  end

  def test_restores_the_status_line_plastic_replaced
    original = { "type" => "command", "command" => "mine" }
    FileUtils.mkdir_p(File.join(@plastic_home, ".cache"))
    File.write(File.join(@plastic_home, ".cache", "original-statusline.json"), JSON.generate(original))
    edit_settings { |settings| settings.merge("statusLine" => { "type" => "command", "command" => plastic_statusline }) }
    call("config", "set", "statusline", "true")
    call("install", "--reinstall")
    call("uninstall", "1")

    assert_equal original, settings["statusLine"]
  end

  def test_keeps_a_status_line_the_user_set
    edit_settings { |settings| settings.merge("statusLine" => { "type" => "command", "command" => "mine" }) }
    call("uninstall", "1")

    assert_equal "mine", settings.dig("statusLine", "command")
  end

  private

  def settings_path = File.join(claude_folder, "settings.json")

  def settings = JSON.parse(File.read(settings_path))

  def edit_settings = File.write(settings_path, JSON.generate(yield(settings)))

  def plastic_statusline = File.join(claude_folder, "plastic", "hooks", "plastic-statusline")
end
