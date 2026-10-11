# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/config_list"

class ConfigListTest < Plastic::TestCase
  def list(*words) = plastic("config", "list", *words, table: Plastic::CLI::TABLE)

  def lines(result) = result.out.lines.map { |line| line.squeeze(" ").strip }

  def test_the_global_settings_are_listed_with_their_values
    result = list

    assert_equal [0, ""], [result.code, result.err]
    assert_includes lines(result), "runner.stop_hook false"
    refute(lines(result).any? { |line| line.start_with?("agents.") })
  end

  def test_a_harness_lists_its_own_agent_models
    assert_includes lines(list("--harness", "codex")), "agents.models.plastic-executor gpt-5.6-terra"
  end

  def test_a_value_the_file_sets_is_listed_in_place_of_the_default
    File.write(File.join(@plastic_home, "config.yml"), "global:\n  statusline: false\n")

    assert_includes lines(list), "statusline false"
  end

  def test_the_next_step_changes_a_setting
    assert_includes list.out, "next: plastic config set KEY VALUE"
  end

  def test_an_unregistered_harness_is_refused_with_the_registered_names
    result = list("--harness", "cursor")

    assert_equal 2, result.code
    assert_includes result.out + result.err, "no harness cursor; the registered harnesses are claude-code, codex, hermes"
  end
end
