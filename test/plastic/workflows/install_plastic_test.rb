# frozen_string_literal: true

require_relative "../commands/installer_helper"
require_relative "../../../scripts/lib/plastic/workflows/install_plastic"

class InstallPlasticTest < Plastic::TestCase
  include InstallerHelper

  def install(**choices)
    facts = { claude: false, codex: false, hermes: false, all: false, reinstall: false, force: false }.merge(choices)
    run_workflow(Plastic::Workflows::InstallPlastic, **facts)
  end

  def manifest = File.join(@home, ".claude", "plastic", "manifest.json")

  def test_installs_the_core_files_and_registers_claude
    claude_folder

    outcome, context = install

    assert_equal [:done, package_version], [outcome, context.installed]
    assert_equal "#{package_version}\n", File.read(File.join(@plastic_home, "VERSION"))
    assert_path_exists manifest
  end

  def test_an_agent_already_registered_is_refused_without_reinstall
    claude_folder
    install
    before = File.read(manifest)

    outcome, = install

    assert_equal [Plastic::Refused, "Plastic is already installed for every chosen agent; pass --reinstall to sync the files again"],
      [outcome.class, outcome.message]
    assert_equal before, File.read(manifest)
  end

  def test_a_reinstall_syncs_the_registered_agent_again
    claude_folder
    install

    assert_equal :done, install(reinstall: true).first
  end

  def test_settings_that_do_not_parse_fail_with_no_file_written
    File.write(File.join(claude_folder, "settings.json"), "{ broken")

    outcome, = install

    assert_includes outcome.message, "settings.json is not valid JSON; nothing was changed"
    refute_path_exists File.join(@plastic_home, "VERSION")
  end
end
