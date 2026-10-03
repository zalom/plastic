# frozen_string_literal: true

require_relative "installer_helper"

class InstallCommandTest < Plastic::TestCase
  include InstallerHelper

  def test_a_dry_run_lists_every_core_file_and_changes_no_home
    absent = File.join(@home, "absent", ".plastic")
    result = call("install", "--dry-run", env: { "PLASTIC_HOME" => absent })

    assert_equal 0, result.code
    assert_match(%r{add:\s+bin/plastic}, result.out)
    refute_path_exists absent
  end

  def test_a_dry_run_names_the_files_it_would_replace
    installed("2.0.1")
    File.write(File.join(@plastic_home, "PLASTIC.md"), "old\n")
    before = tree_snapshot(@plastic_home)
    result = call("install", "--dry-run")

    assert_match(/replace:\s+PLASTIC\.md/, result.out)
    assert_equal before, tree_snapshot(@plastic_home)
  end

  def test_installs_the_core_files_and_registers_the_agent
    claude_folder
    result = call("install", "--claude")

    assert_equal 0, result.code, result.err
    assert_equal "#{package_version}\n", File.read(File.join(@plastic_home, "VERSION"))
    assert_path_exists File.join(@home, ".claude", "plastic", "manifest.json")
  end

  def test_refuses_to_install_over_a_registered_agent_without_reinstall
    claude_folder
    call("install", "--claude")
    result = call("install", "--claude")

    assert_equal 3, result.code
    assert_includes result.err, "--reinstall"
  end
end
