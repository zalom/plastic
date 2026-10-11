# frozen_string_literal: true

require_relative "installer_helper"
require_relative "../../../scripts/lib/plastic/installations"

class InstallCommandTest < Plastic::TestCase
  include InstallerHelper

  ENOLA_INSTALLER = "curl -fsSL https://raw.githubusercontent.com/enola-labs/enola/main/install.sh | sh"

  def test_a_dry_run_lists_every_core_file_and_changes_no_home
    absent = File.join(@home, "absent", ".plastic")
    result = call("install", "--dry-run", env: { "PLASTIC_HOME" => absent })

    assert_equal 0, result.code
    assert_match(%r{add:\s+bin/plastic}, result.out)
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
    assert_match(/Enola maps the code architecture of a project.*It is optional.*#{Regexp.escape(ENOLA_INSTALLER)}/m, result.out)
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
