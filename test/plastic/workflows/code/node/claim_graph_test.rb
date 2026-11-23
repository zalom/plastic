# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/node/claim"

class ClaimGraphTest < Plastic::TestCase
  def setup
    super
    open_intent
    @work = store_graphs.work
    @work.approve_intent("1")
    @work.activate_intent("1")
    2.times { |index| @work.add_node(intent_id: "1", title: "Node #{index}", criterion: "it runs") }
  end

  def claim(id = "n1") = run_workflow(Plastic::Workflows::Code::Node::Claim, harness: scoped_harness(session: "s-1"), intent_id: "1", id:, agent: "")

  def put_edge(from, to) = store_graphs.databases.fetch(:store).transaction { |batch| batch.put(:edges, { intent_id: "1", from:, to:, kind: "needs" }, statement: :insert) }

  def test_the_first_claim_is_refused_on_a_loop_and_names_the_nodes_and_the_repair
    put_edge("n1", "n2")
    put_edge("n2", "n1")

    error = assert_raises(Plastic::Refused) { claim }

    assert_equal "the graph of intent 1 has a finding that stops the first claim: nodes loop: n1 -> n2 -> n1; repair: plastic edge remove 1 n2 n1", error.message
    assert_equal "open", retrieval.node("1", "n1").state
  end

  def test_the_first_claim_is_refused_on_a_need_on_a_removed_node
    @work.add_edge(intent_id: "1", from: "n1", to: "n2")
    @work.remove_node(intent_id: "1", id: "n1", reason: "gone")

    error = assert_raises(Plastic::Refused) { claim("n2") }

    assert_match(/node n2 needs n1, which is removed; repair: plastic edge remove 1 n1 n2/, error.message)
  end

  def test_a_later_claim_is_not_refused_on_a_loop
    claim
    @work.release_node(intent_id: "1", id: "n1")
    2.times { |index| @work.add_node(intent_id: "1", title: "Loop #{index}") }
    put_edge("n3", "n4")
    put_edge("n4", "n3")

    assert_equal :done, claim("n1").first
  end

  def test_the_first_claim_prints_the_other_findings
    printed = claim.last.printed

    assert_includes printed, "finding: node n1 has no edge"
    assert_includes printed, "finding: the graph has 2 nodes and no edge at all"
  end

  def test_the_first_claim_claims_though_it_prints_findings
    claim

    assert_equal "claimed", retrieval.node("1", "n1").state
  end

  def test_the_first_claim_of_a_clean_graph_prints_no_finding
    @work.add_edge(intent_id: "1", from: "n1", to: "n2")
    write("#{retrieval.intent("1").dir}/spec.md", "## Done criteria\n- It works\n")
    sync_up

    assert_empty claim.last.printed.grep(/\Afinding:/)
  end

  def test_a_later_claim_prints_no_finding
    claim
    @work.release_node(intent_id: "1", id: "n1")

    assert_empty claim.last.printed.grep(/\Afinding:/)
  end
end
