# frozen_string_literal: true

require_relative "../../../test_helper"

class NodeImpedeTest < Plastic::TestCase
  def cli(*args) = plastic(*args, table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })

  def setup
    super
    open_keyed_intent
    cli("node", "add", "1", "a", "--criterion", "done")
  end

  def test_impeding_a_claimed_node_offers_the_resolution
    cli("node", "claim", "1", "n1")

    result = cli("node", "impede", "1", "n1", "no access to the host")

    assert_call result, code: 0,
      out: "node: n1 impeded\nwrote:  1 node and 1 work log line in work_graph.db\nfiles:  store/1--alpha/work.log\n        store/1--alpha/graph.json\n\nnext: plastic node resolve 1 n1 TEXT\nbecause: node n1 is impeded\n"
  end

  def test_the_impediment_is_stored_as_the_reason
    cli("node", "claim", "1", "n1")
    cli("node", "impede", "1", "n1", "no access to the host")

    assert_equal ["impeded", "no access to the host"], retrieval.node("1", "n1").to_h.values_at(:state, :reason)
  end

  def test_impeding_an_open_node_is_refused
    result = cli("node", "impede", "1", "n1", "no access")

    assert_call result, code: 3, err: "plastic: refused, node n1 is open; it cannot move to impeded\nThis step belongs to the owner. Stop and ask; do not retry with a flag.\n"
  end
end
