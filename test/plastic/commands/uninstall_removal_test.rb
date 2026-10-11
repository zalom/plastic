# frozen_string_literal: true

require_relative "installer_helper"

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

  def test_removes_the_hook_entries_that_run_plastic
    FileUtils.mkdir_p(File.join(@home, ".codex"))
    call("init", "2")
    call("uninstall", "a")

    left = [File.join(@home, ".claude", "settings.json"), File.join(@home, ".codex", "hooks.json")]
      .select { |path| File.file?(path) && File.read(path).match?(/hook (resume|record)/) }

    assert_empty left
  end
end
