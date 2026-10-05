# frozen_string_literal: true

require_relative "../../test_helper"

class TraversalTest < Plastic::TestCase
  def traverse(routine, facts)
    ctx = Plastic::Context.new(declared: routine.chain.facts + facts.keys, facts:, graphs: {})
    run = Plastic::RoutineRun.fresh("kernel test", "ada")
    Plastic::Routine::Traversal.new(routine.chain, ctx, run) { |saved| store_graphs.work.save_routine_run(saved) }.call
  end

  def kept = retrieval.routine_run("kernel test", "ada")

  def test_a_chain_that_reaches_noop_finishes_on_the_last_outcome
    value = traverse(Fixtures::TwoStep, name: "ada")

    assert_equal Plastic::Finished.new(next_command: "plastic kernel two ada", because: "greeted ada"), value
  end

  def test_the_kept_row_lists_every_workflow_the_pass_finished
    traverse(Fixtures::TwoStep, name: "ada")

    assert_equal ["finished", %i[code_stamp code_greet]], [kept.status, kept.finished]
  end

  def test_a_gate_ends_the_pass_on_its_value_and_keeps_it
    value = traverse(Fixtures::Gate, mode: "hold")

    assert_equal Plastic::Refused.new(:code_hold, "the owner holds hold"), value
    assert_equal "refused", kept.status
  end

  def test_an_agent_workflow_ends_the_pass_on_its_hand_off
    traverse(Fixtures::Draft, name: "ada", dir: @home)

    assert_equal ["handed_off", :agent_write_draft], [kept.status, kept.at]
  end

  def test_a_closing_line_with_a_hole_fails_the_pass
    value = traverse(Fixtures::Holed, {})

    assert_equal [Plastic::Failed, "closing"], [value.class, value.step]
  end
end
