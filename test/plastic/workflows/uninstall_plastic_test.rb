# frozen_string_literal: true

require_relative "../commands/installer_helper"
require_relative "../../../scripts/lib/plastic/workflows/uninstall_plastic"
require_relative "../../../scripts/lib/plastic/installations"

class UninstallPlasticTest < Plastic::TestCase
  include InstallerHelper

  def uninstall(*picked) = run_workflow(Plastic::Workflows::UninstallPlastic, picked:, harnesses: picked.join(", "))

  def setup
    super
    claude_folder
    FileUtils.mkdir_p(File.join(@home, ".codex"))
    call("init", "a")
    activated("2.0.3")
  end

  def test_the_picked_harness_is_removed_and_the_home_stays
    outcome, = uninstall("claude-code")

    assert_equal :done, outcome
    refute_path_exists File.join(@home, ".claude", "plastic", "manifest.json")
    assert_equal [["codex"], true], [Plastic::Installations.recorded(@plastic_home), File.exist?(File.join(@plastic_home, "VERSION"))]
  end

  def test_the_releases_stay_while_another_harness_is_recorded
    uninstall("claude-code")

    assert_path_exists share
  end

  def test_the_releases_go_once_no_harness_stays_recorded
    uninstall("claude-code", "codex")

    refute_path_exists share
  end
end
