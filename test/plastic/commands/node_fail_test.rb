# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/node_fail"

class NodeFailTest < Plastic::TestCase
  def cli(*args) = plastic(*args, table: Plastic::CLI::TABLE)

  def setup
    super
    open_intent
    cli("node", "add", "1", "a", "--criterion", "done")
  end

  def test_failing_a_claimed_node_offers_the_release
    cli("node", "claim", "1", "n1")

    result = cli("node", "fail", "1", "n1", "--reason", "boom")

    assert_call result, code: 0, out: "node: n1 failed\nwrote:  1 node in work_graph.db\n\nnext: plastic node release 1 n1 --project global\nbecause: node n1 is failed\n"
  end

  def test_failing_an_open_node_is_refused
    result = cli("node", "fail", "1", "n1", "--reason", "boom")

    assert_call result, code: 1, err: "plastic: code_fail_node, gate: node n1 is open; it cannot move to failed\n"
  end

  def test_a_refused_move_moves_on_the_next_call
    cli("node", "fail", "1", "n1", "--reason", "boom")
    cli("node", "claim", "1", "n1")

    result = cli("node", "fail", "1", "n1", "--reason", "boom")

    assert_call result, code: 0, out: ["node: n1 failed"]
  end

  def test_failing_a_missing_node_names_it
    result = cli("node", "fail", "1", "n9", "--reason", "boom")

    assert_call result, code: 1, err: "plastic: code_fail_node, gate: no node n9 in intent 1\n"
  end

  def test_a_move_takes_the_intent_and_the_node_as_its_subject
    description = Plastic::Commands::NodeFail.describe

    assert_equal [:intent_id, :id], description.subject
    assert_equal [["ID", "the intent"], ["NODE", "the node"]],
      description.arguments.map { |argument| argument.values_at(:label, :text) }
  end
end
