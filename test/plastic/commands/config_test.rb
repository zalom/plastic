# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/commands/config"

class ConfigChoiceScreenTest < Plastic::TestCase
  QUESTION = ["question: Which settings are on?", "choices: 1 [ ] statusline",
    "answer: answer with numbers separated by commas (1,2), a for all, or q to leave with no change"].freeze

  def test_with_no_terminal_the_numbered_list_and_the_answer_line_print
    assert_case line("config"), code: 0, out: [*QUESTION, "next: plastic config <answer>"]
  end

  def test_an_answer_saves_the_settings_it_turns_on
    assert_case line("config 1"), code: 0,
      out: ["statusline true", "screens false", "advisor.enabled false", "next: plastic config list"]
  end

  def test_the_list_of_one_harness_offers_the_answer_for_that_harness
    assert_case line("config --harness codex"), code: 0, out: [*QUESTION, "next: plastic config --harness codex <answer>"]
  end
end

class ConfigCommandTest < Plastic::TestCase
  def config(*words) = plastic("config", *words, table: Plastic::CLI::TABLE)

  def path = File.join(@plastic_home, "config.yml")

  def saved = YAML.safe_load_file(path, aliases: true)

  def test_with_no_terminal_the_on_off_settings_are_listed_for_the_person
    result = config

    assert_equal [0, ""], [result.code, result.err]
    assert_includes result.out, "[x] screens"
    assert_includes result.out, "[ ] runner.stop_hook"
  end

  def test_the_statusline_is_listed_off_by_default
    assert_includes config.out, "[ ] statusline"
  end

  def test_the_daily_backups_are_listed_off_by_default
    assert_includes config.out, "[ ] backup.daily"
  end

  def test_with_no_terminal_the_next_step_asks_the_person
    assert_includes config.out, "next: plastic config <answer>"
  end

  def numbers = config.out.lines.grep(/\[[ x]\]/).to_h { |line| [line[/\] (\S+)/, 1], line[/(\d+)\s+\[/, 1]] }

  def test_the_listed_next_step_keeps_the_harness
    assert_includes config("--harness", "codex").out, "next: plastic config --harness codex <answer>"
  end

  def test_an_answer_turns_on_the_picked_settings_and_writes_only_the_changes
    result = config(numbers.values_at("screens", "advisor.enabled", "runner.stop_hook").join(","))

    assert_equal 0, result.code
    assert_equal({ "runner" => { "stop_hook" => true } }, saved["global"])
  end

  def test_an_unpicked_setting_that_was_on_is_turned_off
    config(numbers.values_at("screens").join(","))

    assert_equal({ "advisor" => { "enabled" => false } }, saved["global"])
  end

  def test_an_answer_with_a_harness_writes_under_that_harness
    config("q")
    config("a", "--harness", "codex")

    assert_equal({ "codex" => { "statusline" => true, "runner" => { "stop_hook" => true }, "migrate" => { "remove_after_import" => true, "drop_document_revisions" => true },
                                "sync" => { "references" => true }, "backup" => { "daily" => true } } }, saved["harnesses"])
  end

  def test_an_answer_that_keeps_every_setting_writes_nothing
    result = config(numbers.values_at("screens", "advisor.enabled").join(","))

    assert_equal [0, false], [result.code, File.exist?(path)]
    assert_includes result.out, "because: nothing changed"
  end

  def test_leaving_changes_nothing
    result = config("q")

    assert_equal [0, false], [result.code, File.exist?(path)]
  end

  def test_an_answer_off_the_list_is_a_usage_error
    assert_equal 2, config("99").code
  end
end
