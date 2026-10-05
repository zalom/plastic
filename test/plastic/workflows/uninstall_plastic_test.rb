# frozen_string_literal: true

require_relative "../commands/installer_helper"
require_relative "../../../scripts/lib/plastic/workflows/install_plastic"
require_relative "../../../scripts/lib/plastic/workflows/uninstall_plastic"

class UninstallPlasticTest < Plastic::TestCase
  include InstallerHelper

  def choices(**chosen) = { claude: false, codex: false, hermes: false, all: false, reinstall: false, force: false }.merge(chosen)

  def install(**chosen) = run_workflow(Plastic::Workflows::InstallPlastic, **choices(**chosen))

  def uninstall(**chosen) = run_workflow(Plastic::Workflows::UninstallPlastic, **choices(**chosen))

  def setup
    super
    claude_folder
    FileUtils.mkdir_p(File.join(@home, ".codex"))
    install(all: true)
    activated("2.0.3")
  end

  def test_the_chosen_agent_files_are_removed_and_the_home_stays
    outcome, = uninstall(claude: true)

    assert_equal :done, outcome
    refute_path_exists File.join(@home, ".claude", "plastic", "manifest.json")
    assert_path_exists File.join(@plastic_home, "VERSION")
  end

  def test_the_releases_stay_while_another_agent_is_registered
    uninstall(claude: true)

    assert_path_exists share
  end

  def test_the_releases_go_once_no_agent_stays_registered
    uninstall(all: true)

    refute_path_exists share
  end
end
