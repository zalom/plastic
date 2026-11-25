# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "package_fixture"
require "plastic/installations/advisor_migration"

class AdvisorMigrationTest < Plastic::TestCase
  include PackageFixture

  Migration = Plastic::Installations::AdvisorMigration

  def test_the_former_advisor_names_move_to_the_current_names
    config = { "advisor" => { "claude" => { "default" => "plastic-advisor" } }, "agents" => { "models" => { "claude" => { "plastic-faux-advisor" => "opus" } } } }
    migrated = Migration.call(config)

    assert_equal ["plastic-primary-advisor", { "plastic-secondary-advisor" => "opus" }], [migrated.dig("advisor", "claude", "default"), migrated.dig("agents", "models", "claude")]
  end

  def test_a_current_key_is_kept_over_a_former_one_and_the_input_is_not_changed
    config = { "agents" => { "efforts" => { "plastic-advisor" => "low", "plastic-primary-advisor" => "high" } } }

    assert_equal({ "plastic-primary-advisor" => "high" }, Migration.call(config).dig("agents", "efforts"))
    assert_includes config.dig("agents", "efforts"), "plastic-advisor"
  end

  def test_a_value_that_is_not_a_mapping_gives_an_empty_config
    assert_equal({}, Migration.call("text"))
  end

  def test_a_config_file_with_a_former_name_is_rewritten_once
    path = config_with("advisor:\n  claude:\n    default: plastic-advisor\n")

    assert_equal [true, false, "plastic-primary-advisor"], [Migration.file(path), Migration.file(path), YAML.safe_load_file(path).dig("advisor", "claude", "default")]
  end

  def test_a_missing_or_unreadable_config_file_changes_nothing
    path = write(File.join(@home, "bad.yml"), "- list\n")

    assert_equal [false, false, false, false], [Migration.file(nil), Migration.file(File.join(@home, "absent.yml")), Migration.file(path), Migration.file(write(File.join(@home, "worse.yml"), ": [\n"))]
  end
end
