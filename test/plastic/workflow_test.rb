# frozen_string_literal: true

require_relative "../test_helper"

class WorkflowTest < Plastic::TestCase
  def test_a_key_is_the_lane_and_the_snake_name
    assert_equal :code_find_draft, Flows::FindDraft.key
    assert_equal :agent_write_draft, Flows::WriteDraft.key
  end

  module Unregistered
    class Flow < Plastic::Workflow; end
  end

  def test_a_workflow_in_no_namespace_that_holds_a_registry_has_no_key
    error = assert_raises(Plastic::Invalid) { Unregistered::Flow.key }

    assert_equal "WorkflowTest::Unregistered::Flow sits in no namespace that holds a REGISTRY", error.message
  end

  def test_a_workflow_needs_a_lane
    assert_raises(NoMethodError) { Class.new(Plastic::Workflow).lane }
  end

  def test_fetch_finds_a_loaded_workflow
    assert_equal Flows::Greet, Plastic::Workflow.fetch(:code_greet, from: Flows)
  end

  def test_fetch_asks_the_caller_for_the_namespace_of_the_registry
    error = assert_raises(ArgumentError) { Plastic::Workflow.fetch(:code_greet) }

    assert_includes error.message, "from"
  end

  def test_fetch_refuses_a_key_whose_lane_does_not_match
    error = assert_raises(Plastic::Invalid) { Plastic::Workflow.fetch(:agent_greet, from: Flows) }

    assert_equal "agent_greet names a agent workflow, and #{Flows::Greet} is a code workflow", error.message
  end

  def test_fetch_loads_the_file_of_a_workflow_not_loaded_yet
    error = assert_raises(LoadError) { Plastic::Workflow.fetch(:code_stamp, from: Module.new.tap { |m| m.const_set(:REGISTRY, { code_stamp: "Stamp" }) }) }

    assert_includes error.message, "workflows/stamp"
  end

  def test_sets_declares_the_facts_a_workflow_writes
    assert_equal [:draft_path], Flows::FindDraft.facts
  end

  def test_an_outcome_takes_only_known_options
    error = assert_raises(Plastic::Invalid) { code { outcome :done, when: 1 } }

    assert_includes error.message, "outcome done does not take when"
  end

  def test_closing_fills_the_offer_and_the_because
    assert_equal ["plastic kernel two ada", "greeted ada"], Flows::Greet.closing(:done, context)
  end

  def test_closing_with_no_offer_names_no_command
    assert_equal [nil, "passed hold"], Flows::Hold.closing(:done, context(facts: { mode: "hold" }))
  end

  def test_closing_with_no_because_raises
    error = assert_raises(Plastic::Invalid) { Flows::Stamp.closing(:done, context) }

    assert_equal "code_stamp ends on done, and no outcome line gives its because:", error.message
  end

  def test_templates_list_every_printed_line
    assert_equal ["plastic kernel two %{name}", "greeted %{name}"], Flows::Greet.templates
  end

  def test_the_base_call_must_be_defined
    assert_raises(NoMethodError) { Class.new(Plastic::Workflow).new(context).call }
  end

  def test_a_gate_stops_only_as_refusal_or_failure
    error = assert_raises(Plastic::Invalid) { code { gate "x", stops: :later, pass: ->(_c) { true } } }

    assert_includes error.message, "a gate stops as :refusal or :failure"
  end

  def test_a_step_needs_a_block
    error = assert_raises(Plastic::Invalid) { code { step "empty", done: ->(_c) { true }, changes: {} } }

    assert_includes error.message, "step \"empty\" needs a block"
  end

  def test_no_outcome_may_follow_the_fallback
    error = assert_raises(Plastic::Invalid) do
      code do
        outcome :done, because: "done"
        outcome :late, because: "late"
      end
    end

    assert_includes error.message, "outcome late follows the fallback done"
  end
end

class WorkflowDeclarationsTest < Plastic::TestCase
  def test_clearing_the_declarations_of_a_workflow_empties_its_facts_and_outcomes
    flow = Class.new(Plastic::Workflow)
    flow.sets :name
    flow.outcome :done, because: "done"
    flow.clear_declarations

    assert_equal [[], []], [flow.facts, flow.outcomes]
  end

  def test_clearing_the_declarations_of_a_code_workflow_empties_its_steps_too
    flow = code do
      sets :name
      gate "stop", stops: :failure, pass: ->(_context) { true }
      outcome :done, because: "done"
    end
    flow.clear_declarations

    assert_equal [[], [], []], [flow.facts, flow.steps, flow.outcomes]
  end

  def test_clearing_the_declarations_of_an_agent_workflow_empties_its_steps_too
    flow = agent do
      step "read", done: ->(_context) { true }, say: "read"
      outcome :done, because: "done"
    end
    flow.clear_declarations

    assert_equal [[], []], [flow.steps, flow.outcomes]
  end

  def test_clearing_the_declarations_leaves_the_lists_of_another_workflow_as_they_are
    kept = code { outcome :done, because: "done" }
    code.clear_declarations

    assert_equal 1, kept.outcomes.size
  end

  def test_a_summary_is_the_one_sentence_of_the_workflow
    flow = code do
      summary "Greets the person by name."
      outcome :done, because: "greeted"
    end

    assert_equal "Greets the person by name.", flow.summary
  end

  def test_a_workflow_with_no_summary_answers_nil
    assert_nil code {}.summary
  end

  def test_clearing_the_declarations_removes_the_summary
    flow = code { summary "Greets." }
    flow.clear_declarations

    assert_nil flow.summary
  end

  def test_a_summary_adds_no_template_and_changes_no_outcome
    flow = code do
      summary "Greets %{name} by name."
      outcome :done, because: "greeted"
    end

    assert_equal ["greeted"], flow.templates
    assert_equal :done, flow.call(context)
  end
end
