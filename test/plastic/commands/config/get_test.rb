# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/config/get"

class ConfigGetScreensTest < Plastic::TestCase
  def test_the_screens_setting_reads_true_before_anything_is_set
    assert_case line("config get screens"), code: 0, out: ["screens true", "next: plastic config set screens VALUE"]
  end

  def test_the_screens_setting_reads_false_after_it_is_set_to_false
    ran("config set screens false")

    assert_case line("config get screens"), code: 0, out: ["screens false", "next: plastic config set screens VALUE"]
  end

  def test_a_harness_reads_its_own_override_and_offers_the_set_for_that_harness
    ran("config set screens false --harness codex")

    assert_case line("config get screens --harness codex"), code: 0,
      out: ["screens false", "next: plastic config set screens VALUE --harness codex"]
  end

  def test_the_global_value_ignores_the_override_of_a_harness
    ran("config set screens false --harness codex")

    assert_case line("config get screens"), code: 0, out: ["screens true", "next: plastic config set screens VALUE"]
  end
end

class ConfigGetTest < Plastic::TestCase
  def get(*words) = plastic("config", "get", *words, table: Plastic::CLI::TABLE)

  def test_a_global_setting_prints_its_value
    result = get("review.pull_request")

    assert_equal [0, ""], [result.code, result.err]
    assert_match(/^review\.pull_request\s+off$/, result.out)
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
