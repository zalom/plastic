# frozen_string_literal: true

require_relative "../../test_helper"

class LinkTest < Plastic::TestCase
  def problems(key, declared: [], &)
    chain = Class.new(Fixtures::Routine, &).chain
    Plastic::Routine::Link.new(chain, key).problems(declared)
  end

  def test_a_sound_link_has_no_problem
    assert_empty(problems(:code_greet, declared: %i[name greeting]) { workflow :code_greet, next: :noop })
  end

  def test_an_outcome_with_no_edge_is_named
    assert_includes problems(:code_stamp) { workflow :code_stamp }, "code_stamp has no edge for done"
  end

  def test_an_edge_for_an_outcome_never_returned_is_named
    link = problems(:code_greet, declared: %i[name greeting]) do
      workflow :code_greet do
        on :done, next: :noop
        on :late, next: :noop
      end
    end

    assert_equal ["code_greet has an edge for late, which it never returns"], link
  end

  def test_an_agent_workflow_with_a_successor_is_named
    link = problems(:agent_review) do
      workflow :agent_review, next: :code_break
      workflow :code_break, next: :noop
    end

    assert_equal ["agent_review is an agent workflow and must end the chain"], link
  end

  def test_an_ending_with_no_because_is_named
    assert_equal ["code_stamp ends on done, and no outcome line gives its because:"], problems(:code_stamp) { workflow :code_stamp, next: :noop }
  end

  def test_a_printed_fact_no_one_declares_is_named
    assert_equal ["code_hold prints %{mode}, which no one declares"], problems(:code_hold) { workflow :code_hold, next: :noop }
  end
end
