# frozen_string_literal: true

require_relative "../../test_helper"

class ChainTest < Plastic::TestCase
  def routine(&body)
    Class.new(Fixtures::Routine) do
      argument :name, label: "NAME", text: "a name"
      class_eval(&body)
    end
  end

  def test_a_sound_chain_has_no_problems
    assert_empty Fixtures::Draft.chain_problems
  end

  def test_verify_lists_every_problem_in_one_message
    broken = routine do
      workflow :code_stamp, next: :code_missing
      workflow :code_hold, next: :code_stamp
    end
    error = assert_raises(Plastic::Invalid) { broken.verify }

    expected = ["code_missing is a target but not in the chain",
      "code_hold -> code_stamp points backward; a chain only moves forward",
      "code_hold prints %{mode}, which no one declares"]

    assert_empty expected.reject { |problem| error.message.include?(problem) }
  end

  def test_an_undeclared_fact_is_a_problem
    chain = routine { workflow :code_hold, next: :noop }

    assert_includes chain.chain_problems, "code_hold prints %{mode}, which no one declares"
  end

  def test_a_key_missing_from_the_registry_is_the_only_problem
    chain = routine { workflow :code_nowhere, next: :noop }

    assert_equal ["no workflow code_nowhere in Fixtures::Workflows::REGISTRY"], chain.chain_problems
  end

  def test_a_workflow_no_edge_reaches_is_a_problem
    chain = routine do
      workflow :code_stamp, next: :noop
      workflow :code_greet, next: :noop
    end

    assert_includes chain.chain_problems, "code_greet cannot be reached from code_stamp"
  end

  def test_an_outcome_with_no_edge_is_a_problem
    chain = routine { workflow :code_stamp }

    assert_includes chain.chain_problems, "code_stamp has no edge for done"
  end

  def test_an_edge_for_an_outcome_never_returned_is_a_problem
    chain = routine do
      workflow :code_greet do
        on :done, next: :noop
        on :late, next: :noop
      end
    end

    assert_equal ["code_greet has an edge for late, which it never returns"], chain.chain_problems
  end

  def test_an_ending_with_no_because_is_a_problem
    chain = routine { workflow :code_stamp, next: :noop }

    assert_equal ["code_stamp ends on done, and no outcome line gives its because:"], chain.chain_problems
  end

  def test_an_agent_workflow_must_end_the_chain
    chain = routine do
      workflow :agent_review, next: :code_break
      workflow :code_break, next: :noop
    end

    assert_equal ["agent_review is an agent workflow and must end the chain"], chain.chain_problems
  end

  def test_a_workflow_reports_its_own_problems
    chain = routine { workflow :code_choose, next: :noop }

    assert_equal ["code_choose: the last outcome line needs no if:, so that one outcome always holds"],
      chain.chain_problems
  end

  def test_an_on_line_wins_over_the_plain_next
    chain = routine do
      workflow :code_stamp, next: :code_greet do
        on :done, next: :code_break
      end
      workflow :code_greet, next: :noop
      workflow :code_break, next: :noop
    end.chain

    assert_equal :code_break, chain.target(:code_stamp, :done)
  end

  def test_an_outcome_with_no_edge_raises_at_run_time
    chain = routine { workflow :code_stamp }.chain
    error = assert_raises(Plastic::Invalid) { chain.target(:code_stamp, :done) }

    assert_match(/code_stamp has no edge for done\z/, error.message)
  end

  def test_the_entry_is_the_first_key
    assert_equal :code_stamp, Fixtures::Draft.chain.entry
  end
end
