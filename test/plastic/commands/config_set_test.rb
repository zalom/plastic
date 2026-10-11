# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/config_set"

class ConfigSetTest < Plastic::TestCase
  def set(*words) = plastic("config", "set", *words, table: Plastic::CLI::TABLE)

  def path = File.join(@plastic_home, "config.yml")

  def saved = YAML.safe_load_file(path, aliases: true)

  def test_a_global_setting_is_written_under_global
    result = set("runner.stop_hook", "true")

    assert_equal [0, ""], [result.code, result.err]
    assert_equal({ "runner" => { "stop_hook" => true } }, saved["global"])
    assert_includes result.out, "next: plastic config get runner.stop_hook"
  end

  def test_false_is_written_as_false
    result = set("screens", "false")

    assert_equal [0, { "screens" => false }], [result.code, saved["global"]]
  end

  def test_a_harness_setting_is_written_under_that_harness_only
    set("agents.models.plastic-executor", "haiku", "--harness", "claude-code")

    assert_equal [{ "claude-code" => { "agents" => { "models" => { "plastic-executor" => "haiku" } } } }, nil],
      [saved["harnesses"], saved["global"]]
  end

  def test_an_unknown_key_is_refused_and_writes_nothing
    result = set("no.such", "1")

    assert_equal [2, false], [result.code, File.exist?(path)]
  end

  def test_an_on_off_setting_refuses_a_value_that_is_not_true_or_false
    result = set("statusline", "maybe")

    assert_equal [2, false], [result.code, File.exist?(path)]
    assert_includes result.out + result.err, "statusline takes true or false"
  end

  def test_a_list_value_is_refused
    assert_equal 2, set("review.pull_request", "[a, b]").code
  end

  def test_a_value_yaml_reads_as_nothing_is_written_as_its_text
    set("review.pull_request", "~")

    assert_equal({ "review" => { "pull_request" => "~" } }, saved["global"])
  end

  def test_a_value_yaml_cannot_read_is_written_as_its_text
    set("review.pull_request", "'open")

    assert_equal({ "review" => { "pull_request" => "'open" } }, saved["global"])
  end

  def test_an_unregistered_harness_is_refused_and_writes_nothing
    result = set("statusline", "false", "--harness", "cursor")

    assert_equal [2, false], [result.code, File.exist?(path)]
  end
end
