# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/config"
require_relative "../../../lib/plastic/config/import"

class ConfigImportTest < Plastic::TestCase
  def rows(text)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.yml")
      File.write(path, text) if text
      return Plastic::Config::Import.new(path).rows
    end
  end

  def test_a_sectioned_file_gives_a_row_for_each_setting_with_its_scope_and_dotted_key
    text = "version: 3\nglobal:\n  runner:\n    stop_hook: true\nharnesses:\n  codex:\n    advisor:\n      default: x\n"

    assert_equal [["global", "runner.stop_hook", "true"], ["codex", "advisor.default", "\"x\""]], rows(text)
  end

  def test_a_flat_file_is_moved_into_the_sections_first
    text = "agent:\n  type: codex\n  parallel_mode: linear\nagents:\n  models:\n    plastic-executor: haiku\n"

    assert_equal [["global", "agent.parallel_mode", "\"linear\""], ["claude-code", "agents.models.plastic-executor", "\"haiku\""]], rows(text)
  end

  def test_anchors_and_merge_keys_are_resolved_to_plain_values
    text = "global:\n  agents: &shared\n    models:\n      plastic-executor: haiku\n" \
           "harnesses:\n  claude-code:\n    agents:\n      <<: *shared\n"

    assert_equal [["global", "agents.models.plastic-executor", "\"haiku\""], ["claude-code", "agents.models.plastic-executor", "\"haiku\""]], rows(text)
  end

  def test_a_missing_file_gives_no_rows
    assert_empty rows(nil)
  end

  def test_a_file_that_does_not_parse_gives_no_rows
    assert_empty rows("runner: [\n")
  end

  def test_a_file_holding_a_plain_list_gives_no_rows
    assert_empty rows("- a\n- b\n")
  end

  def test_the_rows_land_in_the_settings_table_of_a_connection
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.yml")
      File.write(path, "global:\n  screens: false\n")
      db = SQLite3::Database.new(":memory:")
      db.execute("CREATE TABLE settings(scope TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL, UNIQUE(scope, key))")
      Plastic::Config::Import.new(path).call(db)

      assert_equal [["global", "screens", "false"]], db.execute("SELECT scope, key, value FROM settings")
    end
  end
end
