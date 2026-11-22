# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/config/list"

class WorkflowListConfigTest < Plastic::TestCase
  Flow = Plastic::Workflows::Code::Config::List

  def listed(harness: nil)
    context = Plastic::Context.new(declared: Flow.facts + [:harness], facts: { harness: }, graphs: {}, harness: scoped_harness)
    [Flow.call(context), context]
  end

  def test_every_setting_is_printed_as_a_row_with_its_value
    outcome, context = listed

    assert_equal [:done, "off"], [outcome, printed_row(context, "review.pull_request")]
  end

def test_the_worker_limit_is_listed_at_three
  _outcome, context = listed

  assert_equal "3", printed_row(context, "driver.max_workers")
end

  def test_the_next_step_offers_to_set_a_setting
    outcome, context = listed

    assert_equal ["plastic config set KEY VALUE", "the settings are listed"], Flow.closing(outcome, context)
  end

  def test_the_next_step_keeps_the_harness_it_was_called_with
    outcome, context = listed(harness: "codex")

    assert_equal "plastic config set KEY VALUE --harness codex", Flow.closing(outcome, context).first
  end

  def test_a_harness_that_is_not_registered_is_a_usage_error
    assert_raises(Plastic::Usage) { listed(harness: "nosuch") }
  end
end
