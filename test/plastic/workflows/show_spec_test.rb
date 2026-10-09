# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/show_spec"

class WorkflowShowSpecTest < Plastic::TestCase
  def specified(body)
    write("#{open_intent.dir}/spec.md", "# Spec\n\n#{body}")
    sync_up
  end

  def show(intent_id = "1") = run_workflow(Plastic::Workflows::ShowSpec, intent_id:)

  def test_the_grilling_method_is_printed_first
    open_intent

    assert_equal File.read(Plastic::Workflows::ShowSpec::GRILLING), show.last.printed.first
  end

  def test_an_open_decision_ends_on_recording_a_ruling
    specified("## Open decisions\n- Which way\n\n## Done criteria\n- It works\n")

    outcome, context = show

    assert_equal [:open, "open: Which way"], [outcome, context.printed.last]
  end

  def test_a_spec_without_criteria_ends_on_writing_them
    specified("## Goal\n- Ship\n")

    assert_equal :no_criterion, show.first
  end

  def test_a_clear_spec_with_a_go_ahead_is_done
    specified("## Done criteria\n- It works\n")
    store_graphs.work.approve_intent("1")

    assert_equal :done, show.first
  end

  def test_a_clear_spec_without_a_go_ahead_needs_the_agent_to_ask_the_owner
    specified("## Done criteria\n- It works\n")

    outcome, context = show

    assert_equal [:agent_needed, "the owner must give the go-ahead for intent 1"], [outcome, context.why]
  end

  def test_an_unknown_intent_fails_the_call
    assert_equal "code_show_spec, gate: no intent 9 in this store", show("9").first.message
  end
end
