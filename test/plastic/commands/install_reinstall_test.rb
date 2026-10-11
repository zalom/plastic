# frozen_string_literal: true

require_relative "installer_helper"
require_relative "../../../scripts/lib/plastic/doctor"
require_relative "../../../scripts/lib/plastic/installations"

class InstallReinstallTest < Plastic::TestCase
  include InstallerHelper

  def test_a_reinstall_syncs_the_installed_harnesses
    %w[.claude .codex].each { |folder| FileUtils.mkdir_p(File.join(@home, folder)) }
    call("init", "2")
    FileUtils.rm_f(File.join(@home, ".codex", "agents", "plastic-executor.toml"))
    result = call("install", "--reinstall")

    assert_equal 0, result.code, result.err
    assert_equal [true, false], [File.exist?(File.join(@home, ".codex", "agents", "plastic-executor.toml")), File.exist?(File.join(@home, ".claude", "plastic"))]
  end

  def test_a_reinstall_writes_the_record_of_a_harness_installed_before_records
    claude_folder
    call("init", "1")
    FileUtils.rm_rf(Plastic::Installations.folder(@plastic_home))
    call("install", "--reinstall")

    assert_equal ["claude-code"], Plastic::Installations.recorded(@plastic_home)
  end

  def test_a_reinstall_never_writes_into_an_unregistered_harness
    claude_folder
    call("init", "1")
    FileUtils.mkdir_p(File.join(@home, ".hermes", "plastic"))
    File.write(File.join(@home, ".hermes", "plastic", "VERSION"), "2.0.0\n")
    call("install", "--reinstall")

    refute_path_exists File.join(@home, ".hermes", "plastic", "manifest.json")
  end

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

    assert_includes help, "sync the files again and make the global store and local.db when they are missing or behind"
  end

  private

  def machine_key = (Plastic::Graph::Schema.databases.keys - Plastic::Graph::Schema.store).first

  def machine_problem
    Plastic::Doctor::DatabaseCheck.new(File.join(@plastic_home, Plastic::Graph::Schema.file(machine_key)), machine_key).problem
  end
end
