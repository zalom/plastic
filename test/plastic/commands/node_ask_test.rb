# frozen_string_literal: true

require_relative "../../test_helper"

class NodeAskTest < Plastic::TestCase
  def cli(*args) = plastic(*args, table: Plastic::CLI::TABLE)

  def setup
    super
    open_keyed_intent
    cli("node", "add", "1", "a", "--criterion", "done")
  end

  def test_asking_about_a_claimed_node_offers_the_resolution
    cli("node", "claim", "1", "n1")

    result = cli("node", "ask", "1", "n1", "which way?")

    assert_call result, code: 0,
      out: "node: n1 needs_info\nwrote:  1 routine run in local.db\n        1 node in work_graph.db\n\nnext: plastic node resolve 1 n1 TEXT --project global\nbecause: node n1 is needs_info\n"
  end

  def test_asking_about_an_open_node_is_refused
    result = cli("node", "ask", "1", "n1", "which way?")

    assert_call result, code: 1, out: RUN_ROW, err: "plastic: code_ask_node, gate: node n1 is open; it cannot move to needs_info\n"
  end

  def test_the_text_is_required
    assert_equal 2, cli("node", "ask", "1", "n1").code
  end
end
