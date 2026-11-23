# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/work/start_check"

# Each test reads intent 2, opened after intent 1 and its child, so its row id is 3 and differs from its number.
class StartCheckTest < Plastic::TestCase
  def setup
    super
    open_intent("Alpha")
    open_intent("Child", parent_id: "1")
    @intent = open_keyed_intent("Beta")
    @work = store_graphs.work
    2.times { |index| @work.add_node(intent_id: "2", title: "Node #{index}", criterion: "done") }
  end

  def check = Plastic::Graph::Work::StartCheck.new(retrieval, retrieval.intent("2"), store_root)

  def put_edge(from, to) = store_database.transaction { |batch| batch.put(:edges, { intent_id: "2", from:, to:, kind: "needs" }, statement: :insert) }

  def test_the_intent_read_has_a_row_id_other_than_its_number
    refute_equal "2", retrieval.intent("2").id.to_s
  end

  def test_a_loop_stops_the_first_claim_and_names_the_intent_by_its_number
    put_edge("n1", "n2")
    put_edge("n2", "n1")

    assert_equal "the graph of intent 2 has a finding that stops the first claim: nodes loop: n1 -> n2 -> n1; repair: plastic edge remove 2 n2 n1", check.problem
  end

  def test_a_clean_graph_with_a_done_criterion_prints_no_criterion_finding
    @work.add_edge(intent_id: "2", from: "n1", to: "n2")

    assert_empty check.claim_lines.grep(/names no done criterion/)
  end

  def test_the_first_claim_prints_the_findings_of_the_intent
    assert_includes check.claim_lines, "finding: the graph has 2 nodes and no edge at all"
  end

  def test_a_later_claim_prints_no_finding
    @work.claim_node(intent_id: "2", id: "n1", by: "s-1")

    assert_empty check.claim_lines
  end
end
