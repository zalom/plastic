# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/knowledge/findings"

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

  def test_a_done_node_with_blank_findings_names_its_hand_edit
    criteria
    @work.add_node(intent_id: "1", title: "Build")
    finish("n1", findings: " ")
    finding = Findings.new(retrieval, "1").with_repairs.first

    assert_equal [nil, "edit the findings of node n1 in graph.json, then run plastic sync up and plastic graph check 1 again"], [finding.repair, finding.hand]
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

  def test_more_than_three_runs_are_named_and_three_are_not
    node = Plastic::Graph::Work::Node.from_h({ id: "n1" })

    assert_equal ["node n1 retried 4 times", nil], [4, 3].map { |runs| Findings.retry_finding(node, runs) }
  end

  def test_the_runs_of_a_node_the_owner_answered_are_not_named
    node = Plastic::Graph::Work::Node.from_h({ id: "n1", answer: "go on" })

    assert_nil Findings.retry_finding(node, 5)
  end

  def repairs = Findings.new(retrieval, "1").with_repairs.map { |finding| [finding.text, finding.repair] }

  def put_edge(from, to) = store_graphs.databases.fetch(:store).transaction { |batch| batch.put(:edges, { intent_id: "1", from:, to:, kind: "needs" }, statement: :insert) }

  def test_a_node_with_no_edge_names_the_command_that_adds_one
    criteria
    2.times { |index| @work.add_node(intent_id: "1", title: "Node #{index}") }

    assert_equal [["node n1 has no edge", "plastic edge add 1 n1 TO"], ["node n2 has no edge", "plastic edge add 1 n2 TO"]], repairs
  end

  def test_no_done_criterion_names_the_command_that_prints_how_to_write_one
    assert_equal [["intent 1 names no done criterion", "plastic intent spec 1"]], repairs
  end

  def test_a_node_retried_over_the_cap_names_the_command_that_answers_it
    criteria
    @work.add_node(intent_id: "1", title: "Build")
    store_graphs.databases.fetch(:store).transaction do |batch|
      (1..4).each { |number| batch.put(:runs, { intent_id: "1", node_id: "n1", number:, agent: "", session_id: "s-1", started_at: "2026-11-17T01:00:00Z", ended_at: "2026-11-17T01:01:00Z", result: "failed" }) }
    end

    assert_equal [["node n1 retried 4 times", "plastic node resolve 1 n1 TEXT"]], repairs
  end

  def test_a_need_on_a_removed_node_is_named_with_the_command_that_removes_the_edge
    criteria
    2.times { |index| @work.add_node(intent_id: "1", title: "Node #{index}") }
    @work.add_edge(intent_id: "1", from: "n1", to: "n2")
    @work.remove_node(intent_id: "1", id: "n1", reason: "gone")

    assert_equal [["node n2 needs n1, which is removed", "plastic edge remove 1 n1 n2"]], repairs
  end

  def test_a_loop_in_a_hand_edited_graph_is_named_once_with_its_path_and_the_closing_edge_to_remove
    criteria
    3.times { |index| @work.add_node(intent_id: "1", title: "Node #{index}") }
    @work.add_edge(intent_id: "1", from: "n1", to: "n2")
    put_edge("n2", "n3")
    put_edge("n3", "n1")

    assert_equal [["nodes loop: n1 -> n2 -> n3 -> n1", "plastic edge remove 1 n3 n1"]], repairs
  end

  def test_an_edge_list_with_no_loop_names_none
    criteria
    2.times { |index| @work.add_node(intent_id: "1", title: "Node #{index}") }
    @work.add_edge(intent_id: "1", from: "n1", to: "n2")

    assert_empty repairs
  end
end
