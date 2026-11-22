# frozen_string_literal: true

require_relative "installer_helper"
require_relative "../../../lib/plastic/installations"
require_relative "../../../lib/plastic/doctor"

class InstallCommandTest < Plastic::TestCase
  include InstallerHelper

  ENOLA_INSTALLER = "curl -fsSL https://raw.githubusercontent.com/enola-labs/enola/main/install.sh | sh"

  def test_a_dry_run_lists_every_core_file_and_changes_no_home
    absent = File.join(@home, "absent", ".plastic")
    result = call("install", "--dry-run", env: { "PLASTIC_HOME" => absent })

    assert_equal 0, result.code
    assert_match(%r{add:\s+exe/plastic}, result.out)
    refute_path_exists absent
  end

  def test_a_dry_run_lists_only_the_files_the_package_carries
    result = call("install", "--dry-run", env: { "PLASTIC_PACKAGE_ROOT" => fake_package("2.0.5") })

    assert_equal 0, result.code
    refute_match(/add:|replace:/, result.out)
  end

  def test_a_dry_run_names_the_files_it_would_replace
    installed("2.0.1")
    File.write(File.join(@plastic_home, "PLASTIC.md"), "old\n")
    before = tree_snapshot(@plastic_home)
    result = call("install", "--dry-run")

    assert_match(/replace:\s+PLASTIC\.md/, result.out)
    assert_equal before, tree_snapshot(@plastic_home)
  end

  def test_installs_the_core_files_and_offers_init
    claude_folder
    result = call("install")

    assert_equal 0, result.code, result.err
    assert_equal "#{package_version}\n", File.read(File.join(@plastic_home, "VERSION"))
    assert_match(/next:\s+plastic init/, result.out)
  end

  def test_a_first_install_writes_into_no_harness
    claude_folder
    call("install")

    assert_equal [false, []], [File.exist?(File.join(@home, ".claude", "plastic")), Plastic::Installations.recorded(@plastic_home)]
  end

  def test_an_agent_switch_is_a_usage_error
    claude_folder
    result = call("install", "--claude")

    assert_equal [2, false], [result.code, File.exist?(File.join(@plastic_home, "VERSION"))]
  end

  def test_refuses_an_installed_home_without_reinstall_and_names_init
    call("install")
    result = call("install")

    assert_equal 3, result.code
    assert_match(/plastic init.*--reinstall/, result.err)
  end

  def test_a_first_install_offers_enola_as_an_optional_instruction
    result = call("install")

    assert_equal 0, result.code, result.err
    assert_match(/Enola maps the code architecture of a project.*It is optional.*releases\/tag\/v0\.4\.39/m, result.out)
  end

  def test_a_settings_file_that_is_not_json_stops_the_install_and_changes_nothing
    settings = File.join(claude_folder, "settings.json")
    File.write(settings, "{ not json")
    result = call("install")

    assert_equal 1, result.code
    assert_includes result.err, "#{settings} is not valid JSON; nothing was changed"
    assert_equal ["{ not json", false], [File.read(settings), File.exist?(File.join(@plastic_home, "VERSION"))]
  end
end

class InstallReinstallHarnessesTest < Plastic::TestCase
  include InstallerHelper
  include OwnHome

  def test_a_reinstall_syncs_the_installed_harnesses
    %w[.claude .codex].each { |folder| FileUtils.mkdir_p(File.join(@home, folder)) }
    call("init", "2")
    FileUtils.rm_f(File.join(@home, ".codex", "agents", "plastic-executor.toml"))
    result = call("install", "--reinstall")

    assert_equal 0, result.code, result.err
    assert_equal [true, false], [File.exist?(File.join(@home, ".codex", "agents", "plastic-executor.toml")), File.exist?(File.join(@home, ".claude", "plastic"))]
  end

def test_the_driver_role_installs_for_both_harnesses_with_the_default_worker_limit
  %w[.claude .codex].each { |folder| FileUtils.mkdir_p(File.join(@home, folder)) }
  call("init", "2")

  assert_includes File.read(File.join(@home, ".claude", "agents", "plastic-driver.md")), "at most 3 workers at once"
  assert_includes File.read(File.join(@home, ".codex", "agents", "plastic-driver.toml")), "at most 3 workers at once"
end

def test_the_driver_role_prints_the_worker_limit_the_owner_set
  %w[.claude .codex].each { |folder| FileUtils.mkdir_p(File.join(@home, folder)) }
  call("init", "2")
  call("config", "set", "driver.max_workers", "2")
  call("install", "--reinstall")

  assert_includes File.read(File.join(@home, ".claude", "agents", "plastic-driver.md")), "at most 2 workers at once"
  assert_includes File.read(File.join(@home, ".codex", "agents", "plastic-driver.toml")), "at most 2 workers at once"
end

  def test_a_reinstall_syncs_an_existing_hermes_install
    claude_folder
    call("init", "1")
    FileUtils.mkdir_p(File.join(@home, ".hermes", "plastic"))
    File.write(File.join(@home, ".hermes", "plastic", "VERSION"), "2.0.0\n")
    call("install", "--reinstall")

    assert_path_exists File.join(@home, ".hermes", "plastic", "manifest.json")
  end
end

class InstallReinstallRecordTest < Plastic::TestCase
  include InstallerHelper
  include OwnHome

  def test_a_reinstall_writes_the_record_of_a_harness_installed_before_records
    claude_folder
    call("init", "1")
    FileUtils.rm_rf(Plastic::Installations.folder(@plastic_home))
    call("install", "--reinstall")

    assert_equal ["claude-code"], Plastic::Installations.recorded(@plastic_home)
  end
end

class InstallReinstallTest < Plastic::TestCase
  include InstallerHelper
  include OwnHome

  def test_a_reinstall_that_changes_nothing_reports_no_removed_hook_and_makes_no_offer
    %w[.claude .codex].each { |folder| FileUtils.mkdir_p(File.join(@home, folder)) }
    call("init", "a")
    result = call("install", "--reinstall")

    assert_equal 0, result.code, result.err
    assert_equal [false, false], [result.out.include?("Removed"), result.out.include?("Enola")], result.out
  end

  def test_a_reinstall_makes_the_global_store_and_the_machine_database_again
    installed_home_without_stores
    FileUtils.rm_f(File.join(@plastic_home, Plastic::Graph::Schema.file(machine_key)))
    result = call("install", "--reinstall")

    assert_equal 0, result.code, result.err
    assert_equal [nil, nil], [machine_problem, Plastic::Doctor::Core.store_problem(File.join(@plastic_home, "stores", "global"))]
  end

  def test_the_reinstall_option_says_it_makes_the_stores_that_are_missing
    help = call("install", "--help").out

    assert_includes help, "sync the files again and make the global store and plastic.db when they are missing or behind"
  end

  private

  def machine_key = (Plastic::Graph::Schema.databases.keys - Plastic::Graph::Schema.store).first

  def machine_problem
    Plastic::Doctor::DatabaseCheck.new(File.join(@plastic_home, Plastic::Graph::Schema.file(machine_key)), machine_key).problem
  end
end
