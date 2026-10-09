# frozen_string_literal: true

require_relative "installer_helper"
require_relative "../../../scripts/lib/plastic/doctor"

class InstallReinstallTest < Plastic::TestCase
  include InstallerHelper

  def test_a_reinstall_without_agent_options_syncs_the_registered_agents
    %w[.claude .codex].each { |folder| FileUtils.mkdir_p(File.join(@home, folder)) }
    call("install", "--codex")
    result = call("install", "--reinstall")

    assert_equal 0, result.code, result.err
    assert_path_exists File.join(@home, ".agents", "plastic", "manifest.json")
    refute_path_exists File.join(@home, ".claude", "plastic")
  end

  def test_a_reinstall_that_changes_nothing_reports_no_removed_hook_and_makes_no_offer
    %w[.claude .codex].each { |folder| FileUtils.mkdir_p(File.join(@home, folder)) }
    call("install", "--claude", "--codex")
    result = call("install", "--reinstall")

    assert_equal 0, result.code, result.err
    assert_equal [false, false], [result.out.include?("Removed"), result.out.include?("Enola")], result.out
  end

  def test_a_reinstall_makes_the_global_store_and_the_machine_database_again
    FileUtils.mkdir_p(File.join(@home, ".claude"))
    call("install", "--claude")
    Plastic::Graph::Database::ConnectionPool.release(@home)
    FileUtils.rm_rf(File.join(@plastic_home, "stores"))
    FileUtils.rm_f(File.join(@plastic_home, Plastic::Graph::Schema.file(machine_key)))
    result = call("install", "--reinstall")

    assert_equal 0, result.code, result.err
    assert_equal [nil, nil], [machine_problem, Plastic::Doctor::Core.store_problem(File.join(@plastic_home, "stores", "global"))]
  end

  private

  def machine_key = (Plastic::Graph::Schema.databases.keys - Plastic::Graph::Schema.store).first

  def machine_problem
    Plastic::Doctor::DatabaseCheck.new(File.join(@plastic_home, Plastic::Graph::Schema.file(machine_key)), machine_key).problem
  end
end
