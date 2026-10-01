# frozen_string_literal: true

require_relative "../test_helper"

class AgentWorkflowTest < Plastic::TestCase
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
    ctx = context(declared: %i[name draft_path], facts: { name: "ada", draft_path: __FILE__ })

    assert_equal :done, Flows::WriteDraft.call(ctx)
  end

  def test_an_agent_workflow_hands_off_the_steps_left
    ctx = context(declared: %i[name draft_path], facts: { name: "ada", draft_path: "/nowhere/ada.md" })
    expected = Plastic::HandedOff.new(steps: ["Write the draft to /nowhere/ada.md"], next_command: "plastic kernel draft ada",
      because: "the draft for ada is not written yet", exit_code: 0)

    assert_equal expected, Flows::WriteDraft.call(ctx)
  end

  def test_a_done_check_that_raises_fails_the_handoff
    ctx = context(declared: %i[name draft_path], facts: { name: "ada" })
    value = Flows::WriteDraft.call(ctx)

    assert_equal ["agent_write_draft", "handoff"], [value.workflow.to_s, value.step]
    assert_includes value.reason, "TypeError"
  end
end
