# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/config"

class ConfigCommandTest < Plastic::TestCase
  def config(*words) = plastic("config", *words, table: Plastic::CLI::TABLE)

  def path = File.join(@plastic_home, "config.yml")

  def saved = YAML.safe_load_file(path, aliases: true)

  def test_with_no_terminal_the_on_off_settings_are_listed_for_the_person
    result = config

    assert_equal [0, ""], [result.code, result.err]
    assert_includes result.out, "[x] statusline"
    assert_includes result.out, "[ ] runner.stop_hook"
  end

  def test_with_no_terminal_the_next_step_asks_the_person
    assert_includes config.out, "next: plastic config <answer>"
  end

  def numbers = config.out.lines.grep(/\[[ x]\]/).to_h { |line| [line[/\] (\S+)/, 1], line[/(\d+)\s+\[/, 1]] }

  def test_the_listed_next_step_keeps_the_harness
    assert_includes config("--harness", "codex").out, "next: plastic config --harness codex <answer>"
  end

  def test_an_answer_turns_on_the_picked_settings_and_writes_only_the_changes
    result = config(numbers.values_at("statusline", "screens", "advisor.enabled", "runner.stop_hook").join(","))

    assert_equal 0, result.code
    assert_equal({ "runner" => { "stop_hook" => true } }, saved["global"])
  end

  def test_an_unpicked_setting_that_was_on_is_turned_off
    config(numbers.values_at("screens", "advisor.enabled").join(","))

    assert_equal({ "statusline" => false }, saved["global"])
  end

  def test_an_answer_with_a_harness_writes_under_that_harness
    config("q")
    config("a", "--harness", "codex")

    assert_equal({ "codex" => { "runner" => { "stop_hook" => true }, "migrate" => { "remove_after_import" => true } } }, saved["harnesses"])
  end

  def test_leaving_changes_nothing
    result = config("q")

    assert_equal [0, false], [result.code, File.exist?(path)]
  end

  def test_an_answer_off_the_list_is_a_usage_error
    assert_equal 2, config("99").code
  end
end
