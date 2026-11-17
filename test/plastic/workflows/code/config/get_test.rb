# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/config/get"

class WorkflowGetConfigTest < Plastic::TestCase
  include ConfigHomes

  Flow = Plastic::Workflows::Code::Config::Get

  def read(key, harness: nil)
    context = Plastic::Context.new(declared: Flow.facts + %i[key harness], facts: { key:, harness: }, graphs: {}, harness: scoped_harness)
    [Flow.call(context), context]
  end

  def test_a_setting_is_printed_with_its_value
    outcome, context = read("review.pull_request")

    assert_equal [:done, [["review.pull_request", "off"]]], [outcome, printed_rows(context)]
  end

  def test_the_next_step_offers_to_set_the_setting
    outcome, context = read("review.pull_request")

    assert_equal ["plastic config set review.pull_request VALUE", "the setting is printed"], Flow.closing(outcome, context)
  end

  def test_the_next_step_keeps_the_harness_it_was_called_with
    seed_config(@plastic_home, "harnesses:\n  codex:\n    agents:\n      models:\n        plastic-executor: gpt-x\n")
    outcome, context = read("agents.models.plastic-executor", harness: "codex")

    assert_equal ["gpt-x", "plastic config set agents.models.plastic-executor VALUE --harness codex"],
      [printed_row(context, "agents.models.plastic-executor"), Flow.closing(outcome, context).first]
  end

  def test_a_key_that_does_not_exist_is_a_usage_error_that_points_to_the_list
    error = assert_raises(Plastic::CLI::Command::Usage) { read("no.such") }

    assert_equal "no setting no.such; plastic config list names them", error.message
  end
end
