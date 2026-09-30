# frozen_string_literal: true

require_relative "support/kernel"

class WorkflowTest < Minitest::Test
  Flows = KernelFixtures::Workflows

  def context(declared: %i[name mode], facts: {name: "ada"})
    Plastic::Context.new(declared:, facts:, graphs: {}, routine_run: nil)
  end

  def code(&body) = Class.new(Plastic::CodeWorkflow, &body)

  def agent(&body) = Class.new(Plastic::AgentWorkflow, &body)

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
    assert_equal ["none", "passed hold"], Flows::Hold.closing(:done, context(facts: {mode: "hold"}))
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

  def test_a_code_outcome_takes_no_stops
    error = assert_raises(Plastic::Invalid) { code { outcome :done, because: "x", stops: :failure } }

    assert_includes error.message, "outcome done takes no stops:"
  end

  def test_a_code_workflow_with_no_outcome_line_ends_on_done
    assert_equal [:done], Flows::Stamp.outcome_names
    assert_equal :done, Flows::Stamp.call(context(declared: %i[stamp], facts: {}))
  end

  def test_the_first_outcome_whose_check_holds_is_picked
    flow = code do
      outcome :first, if: ->(_c) { false }, because: "first"
      outcome :second, if: ->(_c) { true }, because: "second"
      outcome :rest, because: "rest"
    end

    assert_equal %i[first second rest], flow.outcome_names
    assert_equal :second, flow.call(context)
  end

  def test_the_fallback_is_picked_when_no_check_holds
    flow = code do
      outcome :first, if: ->(_c) { false }, because: "first"
      outcome :rest, because: "rest"
    end

    assert_equal :rest, flow.call(context)
    assert_empty flow.problems
  end

  def test_a_workflow_with_no_outcome_line_has_no_problem
    assert_empty Flows::Stamp.problems
  end

  def test_code_templates_include_the_gate_reasons
    assert_equal ["passed %{mode}", "the owner holds %{mode}", "the check broke on %{mode}"], Flows::Hold.templates
  end

  def test_a_done_step_is_skipped
    ran = []
    flow = code do
      step("once", done: ->(_c) { true }) { |_c| ran << :body }
    end

    assert_equal :done, flow.call(context)
    assert_empty ran
  end

  def test_a_read_runs_on_every_call
    ctx = context(declared: %i[name dir draft_path], facts: {name: "ada", dir: "/d"})
    Flows::FindDraft.call(ctx)

    assert_equal "/d/ada.md", ctx.draft_path
  end

  def test_a_refusal_gate_returns_a_refused_value
    assert_equal Plastic::Refused.new(:code_hold, "the owner holds hold"), Flows::Hold.call(context(facts: {mode: "hold"}))
  end

  def test_a_failure_gate_returns_a_failed_value
    assert_equal Plastic::Failed.new(:code_hold, "gate", "the check broke on break"),
      Flows::Hold.call(context(facts: {mode: "break"}))
  end

  def test_an_agent_workflow_ends_on_handoff_or_done
    error = assert_raises(Plastic::Invalid) { agent { outcome :later, because: "x" } }

    assert_includes error.message, "an agent workflow ends on handoff or done"
  end

  def test_an_agent_outcome_takes_no_if
    error = assert_raises(Plastic::Invalid) { agent { outcome :done, if: ->(_c) { true }, because: "x" } }

    assert_includes error.message, "the kernel picks an agent's outcome, so done takes no if:"
  end

  def test_only_the_handoff_stops_and_only_as_a_failure
    assert_raises(Plastic::Invalid) { agent { outcome :done, because: "x", stops: :failure } }
    assert_raises(Plastic::Invalid) { agent { outcome :handoff, because: "x", stops: :refusal } }
  end

  def test_an_agent_workflow_has_two_outcomes
    assert_equal %i[handoff done], Flows::Review.outcome_names
  end

  def test_agent_templates_include_the_steps
    assert_equal ["the review is open", "reviewed", "Review the change"], Flows::Review.templates
  end

  def test_the_handoff_exit_code_follows_stops
    assert_equal 1, Flows::Review.handoff_exit_code
    assert_equal 0, Flows::WriteDraft.handoff_exit_code
  end

  def test_an_agent_workflow_whose_checks_hold_is_done
    ctx = context(declared: %i[name draft_path], facts: {name: "ada", draft_path: __FILE__})

    assert_equal :done, Flows::WriteDraft.call(ctx)
  end

  def test_an_agent_workflow_hands_off_the_steps_left
    ctx = context(declared: %i[name draft_path], facts: {name: "ada", draft_path: "/nowhere/ada.md"})
    expected = Plastic::HandedOff.new(steps: ["Write the draft to /nowhere/ada.md"], next_command: "plastic kernel draft ada",
      because: "the draft for ada is not written yet", exit_code: 0)

    assert_equal expected, Flows::WriteDraft.call(ctx)
  end

  def test_a_done_check_that_raises_fails_the_handoff
    ctx = context(declared: %i[name draft_path], facts: {name: "ada"})
    value = Flows::WriteDraft.call(ctx)

    assert_equal ["agent_write_draft", "handoff"], [value.workflow.to_s, value.step]
    assert_includes value.reason, "TypeError"
  end
end
