# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/config"

class UpdateConfigImportTest < Plastic::TestCase
  include BackupHomes
  include OldLayoutHomes

  CONFIG = "global:\n  search:\n    source_projects: alpha\nharnesses:\n  claude-code:\n    hooks:\n      enabled: true\n"
  SETTINGS = "SELECT scope, key, value FROM settings ORDER BY scope, key"

  def update_old_layout_home(config = CONFIG)
    @aged_home = old_layout(fresh_home)
    File.write(File.join(@aged_home, "VERSION"), "99.0.0-alpha.1\n")
    File.write(File.join(@aged_home, "config.yml"), config)
    update
  end

  def update = plastic("update", env: { "PLASTIC_HOME" => @aged_home }, table: Plastic::CLI::TABLE)

  def test_an_old_layout_home_brought_current_by_update_has_its_settings_rows_and_a_printed_config
    result = update_old_layout_home

    assert_equal 0, result.code, result.err
    assert_equal [[["claude-code", "hooks.enabled", "true"], ["global", "search.source_projects", "\"alpha\""]], [["config.yml"]]], [rows(SETTINGS), rows("SELECT path FROM printed")]
  end

  def test_the_imported_setting_is_read_by_config
    update_old_layout_home

    assert_equal ["alpha"], Plastic::Wiring.config(@aged_home).source_projects
  end

  def test_a_second_update_changes_no_row
    update_old_layout_home
    before = rows("SELECT * FROM settings ORDER BY scope, key")
    update

    assert_equal before, rows("SELECT * FROM settings ORDER BY scope, key")
  end

  def test_an_unreadable_config_is_named_by_update_and_imports_no_row
    result = update_old_layout_home("global: [unclosed\n")

    assert_includes result.out, "config.yml could not be read"
    assert_empty rows(SETTINGS)
  end

  def rows(sql) = Plastic::Graph::Database.open_local(@aged_home).fetch(:local).rows(sql).map(&:values)
end
