# frozen_string_literal: true

require_relative "installer_helper"
require_relative "../../../scripts/lib/plastic/installations"

class UninstallCommandTest < Plastic::TestCase
  include InstallerHelper

  def setup
    super
    claude_folder
    call("init", "1")
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

  def test_removes_the_hook_entries_that_run_plastic
    FileUtils.mkdir_p(File.join(@home, ".codex"))
    call("init", "2")
    call("uninstall", "a")

    left = [File.join(@home, ".claude", "settings.json"), File.join(@home, ".codex", "hooks.json")]
      .select { |path| File.file?(path) && File.read(path).match?(/hook (resume|record)/) }

    assert_empty left
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
end
