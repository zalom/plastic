# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/config/set"

class ConfigSetMessagesTest < Plastic::TestCase
  def test_a_model_set_for_a_harness_prints_the_setting_and_offers_the_get_for_that_harness
    result = line("config set agents.models.plastic-executor opus --harness codex")

    assert_case result, code: 0, out: ["agents.models.plastic-executor opus",
      "next: plastic config get agents.models.plastic-executor --harness codex"]
  end

  def test_screens_set_to_false_prints_the_setting_and_offers_the_get
    assert_case line("config set screens false"), code: 0, out: ["screens false", "next: plastic config get screens"]
  end

  def test_screens_set_to_maybe_exits_2_and_names_the_two_values
    assert_case line("config set screens maybe"), code: 2, out: "", err: ["screens takes true or false"]
  end

  def test_a_model_set_with_no_harness_exits_2_and_names_the_list
    assert_case line("config set agents.models.plastic-executor opus"), code: 2, out: "",
      err: ["no setting agents.models.plastic-executor; plastic config list names them"]
  end

  def test_an_unregistered_harness_exits_2_and_names_the_registered_ones
    assert_case line("config set screens false --harness gemini"), code: 2, out: "",
      err: ["no harness gemini; the registered harnesses are claude-code, codex, hermes"]
  end
end

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

  def test_the_search_scope_takes_a_comma_value
    result = set("search.source_projects", "global,other")

    assert_equal [0, "global,other"], [result.code, saved.dig("global", "search", "source_projects")]
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
