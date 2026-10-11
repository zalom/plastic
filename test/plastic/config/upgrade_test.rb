# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/config"
require_relative "../../../scripts/lib/plastic/config/upgrade"

class ConfigUpgradeTest < Plastic::TestCase
  def path = File.join(@plastic_home, "config.yml")

  def upgrade(text)
    File.write(path, text)
    Plastic::Config::Upgrade.new(path).call
  end

  def saved = YAML.safe_load_file(path, aliases: true)

  def test_a_retired_agent_key_is_renamed_to_the_agent_that_replaced_it
    text = "global:\n  agents:\n    models:\n      plastic-enforcer: haiku\n" \
           "harnesses:\n  codex:\n    agents:\n      efforts:\n        plastic-enforcer: high\n"

    assert_equal [%w[plastic-enforcer plastic-planner]], upgrade(text)
    assert_equal [{ "plastic-planner" => "haiku" }, { "plastic-planner" => "high" }],
      [saved.dig("global", "agents", "models"), saved.dig("harnesses", "codex", "agents", "efforts")]
  end

  def test_a_retired_agent_key_beside_its_replacement_is_dropped
    text = "global:\n  agents:\n    models:\n      plastic-planner: opus\n      plastic-enforcer: haiku\n"

    assert_equal [%w[plastic-enforcer plastic-planner]], upgrade(text)
    assert_equal({ "plastic-planner" => "opus" }, saved.dig("global", "agents", "models"))
  end

  def test_a_rename_keeps_the_anchors_in_the_file
    text = "global:\n  agents: &shared\n    models:\n      plastic-enforcer: haiku\n" \
           "harnesses:\n  claude-code:\n    agents: *shared\n"
    upgrade(text)

    assert_includes File.read(path), "&shared"
    assert_equal "haiku", saved.dig("harnesses", "claude-code", "agents", "models", "plastic-planner")
  end

  def test_a_file_with_no_retired_agent_is_left_unwritten
    text = "global:\n  agents:\n    models:\n      plastic-executor: haiku\n"

    assert_empty upgrade(text)
    assert_equal text, File.read(path)
  end

  def test_a_file_that_holds_no_mapping_has_no_agent_to_rename
    assert_empty upgrade("- a\n")
  end

  def test_a_flat_file_moves_into_the_layout
    assert_empty upgrade("statusline: true\n")
    assert_equal({ "global" => { "statusline" => true } }, saved)
  end
end
