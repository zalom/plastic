# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../scripts/lib/plastic/graph/knowledge/findings"

class KnowledgeFindingsTest < Plastic::TestCase
  Findings = Plastic::Graph::Knowledge::Findings

  def setup
    super
    @intent = open_intent
    @work = store_graphs.work
  end

  def findings = Findings.new(retrieval, "1").all

  def criteria
    write("#{@intent.dir}/spec.md", "## Done criteria\n- It works\n")
    sync_up
  end

  def finish(id, findings:)
    @work.claim_node(intent_id: "1", id:, by: "a")
    @work.done_node(intent_id: "1", id:, judge: "tests", findings:)
  end

  def test_an_intent_with_criteria_and_one_verified_node_has_no_finding
    criteria
    @work.add_node(intent_id: "1", title: "Build")
    finish("n1", findings: "green")

    assert_empty findings
  end

  def test_an_intent_with_no_criteria_is_named
    assert_equal ["intent 1 names no done criterion"], findings
  end

  def test_a_done_node_with_blank_findings_is_named
    criteria
    @work.add_node(intent_id: "1", title: "Build")
    finish("n1", findings: " ")

    assert_equal ["node n1 is done with no findings"], findings
  end

  def test_a_node_with_no_edge_among_several_is_named
    criteria
    2.times { |index| @work.add_node(intent_id: "1", title: "Node #{index}") }

    assert_equal ["node n1 has no edge", "node n2 has no edge"], findings
  end

  def test_linked_nodes_have_no_edge_finding
    criteria
    2.times { |index| @work.add_node(intent_id: "1", title: "Node #{index}") }
    @work.add_edge(intent_id: "1", from: "n1", to: "n2")

    assert_empty findings
  end

  def test_a_done_node_with_no_findings_is_named
    node = Plastic::Graph::Work::Node.from_h({ id: "n1", state: "done", findings: " " })

    assert_equal "node n1 is done with no findings", Findings.findings_finding(node)
  end

  def test_more_than_three_retries_are_named_and_three_are_not
    nodes = [4, 3].map { |retries| Plastic::Graph::Work::Node.from_h({ id: "n1", retries: }) }

    assert_equal ["node n1 retried 4 times", nil], nodes.map { |node| Findings.retry_finding(node) }
  end
end
