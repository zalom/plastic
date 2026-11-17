# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "install_fixture"
require "plastic/installations/installer"

class InstallerTest < Plastic::TestCase
  include InstallFixture

  Installations = Plastic::Installations

  def installer = Installations::Installer.new(package_root: shipped, plastic_home: plastic, agents: agent_configs, tmp_dirs: [])

  def run_install(selected = %w[claude], **options)
    results = nil
    out, = capture_io { results = installer.install_agents(selected:, **options) }
    [results, out]
  end

  def rows = Installations::Ledger.new(plastic).read

  def test_a_fresh_install_bootstraps_the_store_installs_the_agent_and_records_it
    make_agent_folders(claude_config)
    results, = run_install

    assert_equal [true, "claude", "2.0.3\n"], [results.first[:success], results.first[:key], File.read(File.join(fresh, ".claude", "plastic", "VERSION"))]
    assert_path_exists File.join(plastic, "config.yml")
  end

  def test_a_fresh_install_writes_one_ledger_row_with_the_harness
    make_agent_folders(claude_config)
    run_install

    assert_equal [%w[2.0.3 install claude]], rows.map { |row| row.values_at("version", "action", "harness") }
  end

  def test_a_second_run_is_a_reinstall_and_a_named_action_wins
    make_agent_folders(claude_config)
    run_install
    run_install(ledger_action: "update")

    assert_equal %w[install update], rows.map { |row| row["action"] }
  end

  def test_an_unknown_agent_key_fails_with_that_reason
    results, = run_install(%w[ghost])

    assert_equal [{ agent: "ghost", success: false, reason: "Unknown agent", key: "ghost" }], results
  end

  def test_an_agent_with_no_folder_fails_and_gets_no_ledger_row_for_it
    results, = run_install(%w[hermes])

    refute results.first[:success]
    assert_equal [nil], rows.map { |row| row["harness"] }
  end

  def test_an_agent_already_registered_is_reported_and_not_synced
    make_agent_folders(claude_config)
    results, out = run_install(%w[claude], already_registered: %w[hermes])

    assert_equal [false], results.select { |result| result[:skipped] }.map { |result| result[:success] }
    assert_includes out, "Hermes: already registered, not re-synced"
  end

  def test_a_flat_config_is_moved_into_sections
    make_agent_folders(claude_config)
    write(File.join(plastic, "config.yml"), "version: 3\nscreens: false\n")
    run_install

    assert_equal({ "screens" => false }, YAML.safe_load_file(File.join(plastic, "config.yml")).fetch("global"))
  end

  def test_a_config_file_that_does_not_parse_is_kept_and_the_install_says_so
    make_agent_folders(claude_config)
    write(File.join(plastic, "config.yml"), "global: [unclosed\n")
    _, out = run_install

    assert_match(/config\.yml could not be read \(.+\); fix it and run plastic update/, out)
    assert_equal "global: [unclosed\n", File.read(File.join(plastic, "config.yml"))
  end

  def test_the_version_comes_from_the_package_and_the_channel_from_the_version
    value = Installations::Installer.new(package_root: shipped, plastic_home: plastic, agents: agent_configs, version: "2.1.0-beta.2")

    assert_equal ["2.1.0-beta.2", "beta"], [value.version, value.channel]
  end

  def test_the_installed_version_is_nil_before_any_install
    assert_nil installer.installed_version
  end

  def test_an_update_from_a_home_below_the_settings_rows_names_the_agent_settings_the_config_file_moves
    make_agent_folders(claude_config)
    run_install
    Plastic::Graph::Database::ConnectionPool.release(@home)
    File.write(File.join(plastic, "config.yml"), "global:\n  agents:\n    models:\n      plastic-enforcer: haiku\n")
    File.rename(File.join(plastic, "plastic.db"), File.join(plastic, "local.db"))
    _, out = run_install

    assert_includes out, "config.yml: the settings for plastic-enforcer now apply to plastic-planner."
  end

  def test_an_update_imports_the_config_file_into_the_settings_rows_once
    make_agent_folders(claude_config)
    write(File.join(plastic, "config.yml"), "global:\n  screens: false\n")
    run_install
    write(File.join(plastic, "config.yml"), "global:\n  screens: true\n")
    run_install

    assert_equal [["global", "screens", "false"]], Plastic::Graph::Database.open_local(plastic).fetch(:local).rows("SELECT scope, key, value FROM settings").map(&:values)
  end

  def test_the_installed_agents_are_the_ones_with_a_recorded_version
    make_agent_folders(claude_config)
    run_install

    assert_equal [%w[claude], "2.0.3", true], [installer.installed_agents, installer.installed_version, installer.installed?]
  end
end
