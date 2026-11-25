# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/config/set"

class WorkflowSetConfigTest < Plastic::TestCase
  Flow = Plastic::Workflows::Code::Config::Set

  def write(key, value, harness: nil)
    context = Plastic::Context.new(declared: Flow.facts + %i[key value harness], facts: { key:, value:, harness: }, graphs: {}, harness: scoped_harness)
    [Flow.call(context), context]
  end

  def saved = YAML.safe_load_file(File.join(@plastic_home, "config.yml"), aliases: true)

  def test_a_setting_is_written_under_global_and_printed
    outcome, context = write("runner.stop_hook", "true")

    assert_equal [:done, true, [["runner.stop_hook", "true"]]], [outcome, saved.dig("global", "runner", "stop_hook"), printed_rows(context)]
  end

  def test_the_next_step_offers_to_read_the_setting_back
    outcome, context = write("screens", "false", harness: "claude-code")

    assert_equal ["plastic config get screens --harness claude-code", "the setting is written"], Flow.closing(outcome, context)
  end

  def test_a_setting_of_a_harness_is_written_under_that_harness_only
    write("agents.models.plastic-executor", "haiku", harness: "claude-code")

    assert_equal [{ "claude-code" => { "agents" => { "models" => { "plastic-executor" => "haiku" } } } }, nil], [saved["harnesses"], saved["global"]]
  end

  def test_a_key_that_does_not_exist_is_refused_and_writes_nothing
    assert_raises(Plastic::Usage) { write("no.such", "1") }
    refute_path_exists File.join(@plastic_home, "config.yml")
  end

  def test_an_on_off_setting_refuses_a_value_that_is_not_true_or_false
    error = assert_raises(Plastic::Usage) { write("statusline", "maybe") }

    assert_equal "statusline takes true or false", error.message
  end

  def test_a_list_value_is_refused
    error = assert_raises(Plastic::Usage) { write("review.pull_request", "[a, b]") }

    assert_equal "a setting takes one value, not [a, b]", error.message
  end

  def test_a_value_yaml_reads_as_nothing_is_written_as_its_text
    write("review.pull_request", "~")

    assert_equal "~", saved.dig("global", "review", "pull_request")
  end

  def test_a_value_yaml_cannot_read_is_written_as_its_text
    write("review.pull_request", "'open")

    assert_equal "'open", saved.dig("global", "review", "pull_request")
  end
end
