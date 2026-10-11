# frozen_string_literal: true

require_relative "../commands/installer_helper"
require_relative "../../../scripts/lib/plastic/workflows/install_plastic"

class InstallPlasticTest < Plastic::TestCase
  include InstallerHelper

  def install(**choices)
    facts = { reinstall: false, force: false }.merge(choices)
    run_workflow(Plastic::Workflows::InstallPlastic, **facts)
  end

  def manifest = File.join(@home, ".claude", "plastic", "manifest.json")

  def test_installs_the_core_files_into_no_harness
    claude_folder

    outcome, context = install

    assert_equal [:done, package_version], [outcome, context.installed]
    assert_equal "#{package_version}\n", File.read(File.join(@plastic_home, "VERSION"))
    refute_path_exists manifest
  end

  def test_an_installed_home_is_refused_without_reinstall
    install
    before = tree_snapshot(@plastic_home)

    outcome, = install

    assert_equal [Plastic::Refused, "Plastic is already installed; run plastic init to add a harness, or pass --reinstall to sync the files again"],
      [outcome.class, outcome.message]
    assert_equal before, tree_snapshot(@plastic_home)
  end

  def test_a_reinstall_syncs_the_installed_harness_again
    claude_folder
    call("init", "1")
    FileUtils.rm_f(manifest)

    assert_equal [:done, true], [install(reinstall: true).first, File.exist?(manifest)]
  end

  def test_settings_that_do_not_parse_fail_with_no_file_written
    File.write(File.join(claude_folder, "settings.json"), "{ broken")

    outcome, = install

    assert_includes outcome.message, "settings.json is not valid JSON; nothing was changed"
    refute_path_exists File.join(@plastic_home, "VERSION")
  end
end
