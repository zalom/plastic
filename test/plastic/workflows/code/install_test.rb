# frozen_string_literal: true

require_relative "../../commands/installer_helper"
require_relative "../../../../lib/plastic/workflows/code/install"

class InstallPlasticTest < Plastic::TestCase
  include InstallerHelper
  include BackupHomes
  include OldLayoutHomes

  def install(**choices)
    facts = { reinstall: false, force: false }.merge(choices)
    run_workflow(Plastic::Workflows::Code::Install, **facts)
  end

  def manifest = File.join(@home, ".claude", "plastic", "manifest.json")

  def test_installs_the_core_files_into_no_harness
    claude_folder

    outcome, context = install

    assert_equal [:done, package_version], [outcome, context.installed]
    assert_equal "#{package_version}\n", File.read(File.join(@plastic_home, "VERSION"))
    refute_path_exists manifest
  end

  def test_a_reinstall_over_an_old_layout_home_migrates_the_store_it_backed_up_and_completes_with_the_failed_one_behind
    home = old_layout(fresh_home)
    File.write(store_file(home, "work_graph"), "not a database")
    outcome, context = run_workflow(Plastic::Workflows::Code::Install, reinstall: true, force: false, harness: scoped_harness(env: env_for(home)))

    assert_equal [:done, Plastic::Graph::SchemaMigrator::VERSION, 0], [outcome, *versions_of(home)]
    assert_match(/\A   migrate: alpha stays behind because it could not be migrated \(.*work_graph\.db.*\); fix the cause and run plastic update\z/, context.printed.grep(/migrate:/).first)
  end

  def versions_of(home) = [store_file(home, "knowledge_graph", "beta"), store_file(home, "knowledge_graph")].map { |path| user_versions(home).fetch(path) }

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
