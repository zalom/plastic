# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/node/fail"

class NodeFailTest < Plastic::TestCase
  def cli(*args) = plastic(*args, table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })

  def setup
    super
    open_keyed_intent
    cli("node", "add", "1", "a", "--criterion", "done")
  end

  def test_failing_a_claimed_node_offers_the_release
    cli("node", "claim", "1", "n1", "--agent", "tester")

    result = cli("node", "fail", "1", "n1", "boom")

    assert_call result, code: 0, out: "node: n1 failed\nwrote:  1 node and 1 work log line in work_graph.db\nfiles:  store/1--alpha/work.log\n        store/1--alpha/graph.json\n\nnext: plastic node release 1 n1\nbecause: node n1 is failed\n"
  end

  def test_failing_an_open_node_is_refused
    result = cli("node", "fail", "1", "n1", "boom")

    assert_call result, code: 3, err: "plastic: refused, node n1 is open; it cannot move to failed\nThis step belongs to the owner. Stop and ask; do not retry with a flag.\n"
  end

  def test_a_refused_move_moves_on_the_next_call
    cli("node", "fail", "1", "n1", "boom")
    cli("node", "claim", "1", "n1", "--agent", "tester")

    result = cli("node", "fail", "1", "n1", "boom")

    assert_call result, code: 0, out: ["node: n1 failed"]
  end

  def test_failing_a_missing_node_names_it
    result = cli("node", "fail", "1", "n9", "boom")

    assert_call result, code: 1, err: "plastic: no node n9 in intent 1\n"
  end

  def test_a_move_takes_the_intent_the_node_and_the_reason
    node_fail = Plastic::Commands::Node::Fail

    assert_equal [:intent_id, :id], node_fail.subject
    assert_equal [["ID", "the intent"], ["NODE", "the node"], ["TEXT", "why it failed"]],
      node_fail.arguments.map { |argument| argument.to_h.values_at(:label, :text) }
  end
end
