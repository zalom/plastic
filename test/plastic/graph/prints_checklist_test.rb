# frozen_string_literal: true

require_relative "../../test_helper"

class PrintsChecklistTest < Plastic::TestCase
  APPROVAL = "INSERT INTO approvals(intent_id, origin_id, at, session_id) VALUES ('1', :origin, '2026-10-05T10:00:00+02:00', 's')"
  VERDICT = "INSERT INTO verdicts(intent_id, round, origin_id, verdict, findings, at, session_id) VALUES ('1', 1, :origin, 'accept', 'ok', '2026-10-05T11:00:00+02:00', 's')"

  def printed = Plastic::Graph::Prints.of_intent(retrieval, retrieval.intent("1"))

  def paths = printed.map(&:path)

  def insert(*statements) = store_graphs.databases[:work].transaction { |batch| statements.each { |sql| batch.add(sql, origin:) } }

  def approved_graph
    store_graphs.work.write_intent(title: "One")
    insert(APPROVAL, VERDICT)
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "works")
    JSON.parse(printed.last.text)
  end

  def test_the_graph_file_carries_the_approval_the_verdicts_and_each_nodes_criterion
    graph = approved_graph

    assert_equal ["1", "accept", "works"], [graph.dig("approval", "intent_id"), graph.dig("verdicts", 0, "verdict"), graph.dig("nodes", 0, "criterion")]
  end

  def test_no_context_row_prints_no_context_json
    store_graphs.work.write_intent(title: "One")

    refute_includes paths, "store/1--one/context.json"
  end

  def test_a_context_row_prints_context_json_into_the_intent_folder
    store_graphs.work.write_intent(title: "One")
    row = { intent_id: "1", data: JSON.generate("evidence" => []), updated_at: "2026-10-05T10:00:00+02:00" }
    store_graphs.databases[:knowledge].transaction { |batch| batch.put(:retrieval_contexts, row) }

    assert_includes paths, "store/1--one/context.json"
  end
end
