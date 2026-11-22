# frozen_string_literal: true

require "json"
require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/node/claim"
require_relative "../../../../lib/plastic/commands/graph/check"

# A needed node can hold output that is not JSON when graph.json was edited by hand and synced up. The claim
# refuses before it writes a row, names the node and offers graph check.
class NodeClaimBadOutputTest < Plastic::TestCase
  include LifecycleHelper

  def setup
    super
    specified
    cli("intent", "approve", "1")
    cli("intent", "start", "1")
    cli("node", "add", "1", "Build", "--criterion", KEY)
    cli("node", "add", "1", "Test", "--criterion", KEY)
    cli("edge", "add", "1", "n1", "n2")
    cli("node", "claim", "1", "n1")
    cli("node", "done", "1", "n1", "built")
    hold_output("n1", "not json")
  end

  def hold_output(id, text)
    store_graphs.databases.fetch(:store).transaction do |batch|
      batch.write(:nodes, "UPDATE nodes SET output = '#{text}' WHERE intent_id = '1' AND id = '#{id}'")
    end
  end

  def test_a_claim_with_a_needed_node_that_holds_output_that_is_not_json_fails_and_names_the_node
    result = cli("node", "claim", "1", "n2")

    assert_equal 1, result.code
    assert_equal "plastic: node n1 holds output that is not JSON\n", result.err.lines.first
  end

  def test_the_refused_claim_offers_graph_check
    assert_includes cli("node", "claim", "1", "n2").out, "next: plastic graph check 1\n"
  end

  def test_the_refused_claim_writes_no_run_and_leaves_the_node_open
    cli("node", "claim", "1", "n2")

    assert_equal "open", retrieval.node("1", "n2").state
    assert_empty retrieval.structure.runs("1").select { |run| run.node_id == "n2" }
  end

  def test_the_refusal_is_no_parser_crash
    refute_includes cli("node", "claim", "1", "n2").err, "ParserError"
  end
end
