# frozen_string_literal: true

require_relative "../../commands/installer_helper"

class UpdateConfigImportTest < Plastic::TestCase
  include InstallerHelper
  include OldLayoutHomes

  CONFIG = "global:\n  search:\n    source_projects: alpha\nharnesses:\n  claude-code:\n    hooks:\n      enabled: true\n"
  SETTINGS = "SELECT scope, key, value FROM settings ORDER BY scope, key"

  def update_old_layout_home
    old_layout(@plastic_home)
    File.write(File.join(@plastic_home, "config.yml"), CONFIG)
    installed("99.0.0-alpha.1")
    activated("99.0.0-alpha.1")
    call("update", env: { "PLASTIC_PACKAGE_ROOT" => fake_package("99.0.0-alpha.1"), "PLASTIC_LOCAL_RELEASE" => local_release("99.0.0-alpha.1") })
  end

  def test_an_old_layout_home_brought_current_by_update_has_its_settings_rows_and_a_printed_config
    result = update_old_layout_home

    assert_equal 0, result.code, result.err
    assert_equal [[["claude-code", "hooks.enabled", "true"], ["global", "search.source_projects", "\"alpha\""]], [["config.yml"]]], [rows(SETTINGS), rows("SELECT path FROM printed")]
  end

  def test_the_imported_setting_is_read_by_config
    update_old_layout_home

    assert_equal ["alpha"], Plastic::Config.new(@plastic_home).source_projects
  end

  def test_a_second_update_changes_no_row
    update_old_layout_home
    before = rows("SELECT * FROM settings ORDER BY scope, key")
    call("update", env: { "PLASTIC_PACKAGE_ROOT" => fake_package("99.0.0-alpha.1"), "PLASTIC_LOCAL_RELEASE" => local_release("99.0.0-alpha.1") })

    assert_equal before, rows("SELECT * FROM settings ORDER BY scope, key")
  end

  def rows(sql) = SQLite3::Database.new(File.join(@plastic_home, "plastic.db"), readonly: true).execute(sql)
end
