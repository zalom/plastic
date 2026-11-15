# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/workflows/code/status"

class WorkflowShowStatusTest < Plastic::TestCase
  Flow = Plastic::Workflows::Code::Status

  def status(slug: nil)
    context = Plastic::Context.new(declared: Flow.facts, facts: {}, graphs: {}, harness: scoped_harness(slug:))
    [Flow.call(context), context]
  end

  def test_a_store_with_an_open_intent_is_printed_and_the_next_step_picks_the_work
    open_intent
    outcome, context = status

    assert_equal [:open, ["plastic next", "pick the one to work on"], "global"], [outcome, Flow.closing(outcome, context), printed_row(context, "store:")]
  end

  def test_a_store_with_nothing_open_offers_no_command
    outcome, context = status

    assert_equal [:none, [nil, "nothing is open; ask the person what to work on"]], [outcome, Flow.closing(outcome, context)]
  end

  def test_a_registered_project_without_a_store_that_was_asked_for_offers_to_create_it
    File.write(File.join(@plastic_home, "projects.yml"), "---\nprojects:\n  blog:\n    path: /tmp/blog\n")
    outcome, context = status(slug: "blog")

    assert_equal [:create_store, ["plastic project new blog /tmp/blog", "the project has no store"], "blog has no store folder; run plastic project new blog /tmp/blog"],
      [outcome, Flow.closing(outcome, context), printed_row(context, "store:")]
  end
end
