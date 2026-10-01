# frozen_string_literal: true

require_relative "../test_helper"

class WorkflowTest < Plastic::TestCase
  def test_a_key_is_the_lane_and_the_snake_name
    assert_equal :code_find_draft, Flows::FindDraft.key
    assert_equal :agent_write_draft, Flows::WriteDraft.key
  end

  def test_a_workflow_needs_a_lane
    assert_raises(NoMethodError) { Class.new(Plastic::Workflow).lane }
  end

  def test_fetch_finds_a_loaded_workflow
    assert_equal Flows::Greet, Plastic::Workflow.fetch(:code_greet, from: Flows)
  end

  def test_fetch_refuses_a_key_missing_from_the_registry
    error = assert_raises(Plastic::Invalid) { Plastic::Workflow.fetch(:code_greet) }

    assert_equal "no workflow code_greet in Plastic::Workflows::REGISTRY", error.message
  end

  def test_fetch_refuses_a_key_whose_lane_does_not_match
    error = assert_raises(Plastic::Invalid) { Plastic::Workflow.fetch(:agent_greet, from: Flows) }

    assert_equal "agent_greet names a agent workflow, and #{Flows::Greet} is a code workflow", error.message
  end

  def test_fetch_loads_the_file_of_a_workflow_not_loaded_yet
    error = assert_raises(LoadError) { Plastic::Workflow.fetch(:code_stamp, from: Module.new.tap { |m| m.const_set(:REGISTRY, [:code_stamp]) }) }

    assert_includes error.message, "workflows/stamp"
  end

  def test_sets_declares_facts
    assert_equal [:draft_path], Flows::FindDraft.facts
  end

  def test_an_outcome_takes_only_known_options
    error = assert_raises(Plastic::Invalid) { code { outcome :done, when: 1 } }

    assert_includes error.message, "outcome done does not take when"
  end

  def test_closing_fills_the_offer_and_the_because
    assert_equal ["plastic kernel two ada", "greeted ada"], Flows::Greet.closing(:done, context)
  end

  def test_closing_with_no_offer_prints_none
    assert_equal ["none", "passed hold"], Flows::Hold.closing(:done, context(facts: { mode: "hold" }))
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
    error = assert_raises(Plastic::Invalid) { code { step "empty", done: ->(_c) { true } } }

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
