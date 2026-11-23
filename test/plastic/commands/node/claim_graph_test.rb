# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/node/claim"
require_relative "../../../../lib/plastic/commands/node/add"
require_relative "../../../../lib/plastic/commands/edge/add"

class NodeClaimGraphCaseTest < Plastic::TestCase
  def put_edge(from, to) = store_graphs.databases.fetch(:store).transaction { |batch| batch.put(:edges, { intent_id: "1", from:, to:, kind: "needs" }, statement: :insert) }

  def test_claiming_in_a_graph_with_a_loop_exits_3_and_names_the_nodes_and_the_repair
    alpha_with_node
    ran("node add 1 Test --criterion tests-pass")
    put_edge("n1", "n2")
    put_edge("n2", "n1")

    assert_case line("node claim 1 n1"), code: 3, out: ["next: plastic graph check 1", "because: a loop or a need on a removed node stops the first claim; repair it, then claim again"],
      err: ["the graph of intent 1 has a finding that stops the first claim: nodes loop: n1 -> n2 -> n1; repair: plastic edge remove 1 n2 n1"]
  end
end
