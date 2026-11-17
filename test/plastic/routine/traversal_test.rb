# frozen_string_literal: true

require_relative "../../test_helper"

class TraversalTest < Plastic::TestCase
  def traverse(routine, facts)
    ctx = Plastic::Context.new(declared: routine.chain.facts + facts.keys, facts:, graphs: {})
    run = Plastic::CommandRun.fresh("kernel test", "ada")
    Plastic::Routine::Traversal.new(routine.chain, ctx, run) { |saved| store_graphs.work.save_command_run(saved) }.call { |value| value }
  end

  def kept = retrieval.command_run("kernel test", "ada")

  def test_a_chain_that_reaches_noop_finishes_on_the_last_outcome
    value = traverse(Fixtures::TwoStep, name: "ada")

    assert_equal Plastic::Finished.new(next_command: "plastic kernel two ada", because: "greeted ada"), value
  end

  def test_the_kept_row_lists_every_workflow_the_pass_finished
    traverse(Fixtures::TwoStep, name: "ada")

    assert_equal ["finished", %i[code_stamp code_greet]], [kept.status, kept.finished]
  end

  def test_a_gate_ends_the_pass_on_its_value_and_keeps_it
    error = assert_raises(Plastic::Refused) { traverse(Fixtures::Gate, mode: "hold") }

    assert_equal "the owner holds hold", error.message
    assert_equal "refused", kept.status
  end

  def test_an_agent_workflow_ends_the_pass_on_its_hand_off
    traverse(Fixtures::Draft, name: "ada", dir: @home)

    assert_equal ["handed_off", :agent_write_draft], [kept.status, kept.at]
  end

  def test_a_closing_line_with_a_hole_fails_the_pass
    error = assert_raises(Plastic::Failed) { traverse(Fixtures::Holed, {}) }

    assert_equal "code_hole, closing", error.source
  end
end
