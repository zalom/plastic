# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/config_get"

class ConfigGetTest < Plastic::TestCase
  def get(*words) = plastic("config", "get", *words, table: Plastic::CLI::TABLE)

  def test_a_global_setting_prints_its_value
    result = get("review.pull_request")

    assert_equal [0, ""], [result.code, result.err]
    assert_match(/^review\.pull_request\s+required$/, result.out)
  end

  def test_a_harness_section_value_wins_for_that_harness
    File.write(File.join(@plastic_home, "config.yml"), "harnesses:\n  codex:\n    agents:\n      models:\n        plastic-executor: gpt-x\n")

    assert_match(/^agents\.models\.plastic-executor\s+gpt-x$/, get("agents.models.plastic-executor", "--harness", "codex").out)
  end

  def test_an_unknown_key_is_a_usage_error_that_points_to_the_list
    result = get("no.such")

    assert_equal 2, result.code
    assert_includes result.out + result.err, "no setting no.such; plastic config list names them"
  end

  def test_a_harness_setting_without_a_harness_is_an_unknown_key
    assert_equal 2, get("agents.models.plastic-executor").code
  end
end
