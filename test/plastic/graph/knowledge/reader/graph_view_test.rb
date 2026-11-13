# frozen_string_literal: true

require_relative "../../../../test_helper"

module GraphFileHelpers
  GRAPH = "store/1--alpha/graph.json"

  def node_hash(id, **fields)
    { "intent_id" => "1", "id" => id, "kind" => "work", "title" => "Node #{id}", "criterion" => nil, "state" => "done",
      "by" => "agent-7", "input" => nil, "output" => nil, "question" => nil, "answer" => nil, "reason" => nil,
      "judge" => nil, "verdict" => nil, "findings" => "checked", "retries" => 2, "updated_at" => "2026-10-20T08:00:00Z" }
      .merge(fields.transform_keys(&:to_s))
  end

  def edge_hash(from, to) = { "intent_id" => "1", "from" => from, "to" => to, "kind" => "needs" }

  def graph_text(nodes: [], edges: [], approval: nil, verdicts: [])
    "#{JSON.pretty_generate({ "intent" => "1", "approval" => approval, "verdicts" => verdicts, "nodes" => nodes, "edges" => edges })}\n"
  end

  def sync = (@sync ||= Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases))

  def sync_up_plan = sync.plan(:up)

  def node_rows = retrieval.nodes("1").map(&:to_h)

  def printed_node(title)
    node = store_graphs.work.add_node(intent_id: "1", title:, criterion: "Done")
    store_graphs.work.print_intent("1")
    node
  end
end

class KnowledgeReaderGraphViewTest < Plastic::TestCase
  include GraphFileHelpers

  fixtures :alpha_synced

  def test_sync_up_reads_a_hand_edited_graph_json_into_node_rows_with_the_local_origin
    write(GRAPH, graph_text(nodes: [node_hash("n1")]))
    sync.apply(sync_up_plan)

    assert_equal [["n1", "done", "agent-7", 2, "2026-10-20T08:00:00Z", retrieval.origin_id]],
      node_rows.map { |row| row.values_at(:id, :state, :by, :retries, :updated_at, :origin_id) }
  end

  def test_the_rows_of_the_file_replace_the_node_rows_the_intent_held
    kept = printed_node("Replaced")
    write(GRAPH, graph_text(nodes: [node_hash("n7")]))
    sync.apply(sync_up_plan)

    assert_equal ["n7"], node_rows.map { |row| row[:id] }
    refute_includes node_rows.map { |row| row[:id] }, kept.id
  end

  def write_full_graph
    approval = { "intent_id" => "1", "at" => "2026-10-20T09:00:00Z", "session_id" => "s1" }
    verdict = { "intent_id" => "1", "round" => 1, "verdict" => "accept", "findings" => "fine", "at" => "2026-10-20T10:00:00Z", "session_id" => "s2" }
    write(GRAPH, graph_text(nodes: [node_hash("n1"), node_hash("n2")], edges: [edge_hash("n1", "n2")], approval:, verdicts: [verdict]))
  end

  def test_edges_and_the_approval_are_read_with_the_nodes
    write_full_graph
    sync.apply(sync_up_plan)

    assert_equal [["n1", "n2", "needs"]], retrieval.edges("1").map { |edge| edge.to_h.values_at(:from, :to, :kind) }
    assert_equal "2026-10-20T09:00:00Z", retrieval.approvals("1").first.at
  end

  def test_the_verdicts_are_read_with_the_nodes
    write_full_graph
    sync.apply(sync_up_plan)

    assert_equal [[1, "accept"]], retrieval.verdicts("1").map { |row| row.to_h.values_at(:round, :verdict) }
  end

  def file_and_print = [folder.read(GRAPH), retrieval.printed[GRAPH]]

  def test_a_second_sync_up_leaves_the_file_bytes_and_the_printed_hash_as_they_are
    write(GRAPH, graph_text(nodes: [node_hash("n1")]))
    sync.apply(sync_up_plan)
    before = file_and_print
    again = sync_up_plan

    assert_empty again.taking(:read)
    sync.apply(again)

    assert_equal before, file_and_print
  end

  def test_a_file_and_rows_both_changed_since_the_print_are_a_conflict_and_nothing_is_written
    store_graphs.work.add_node(intent_id: "1", title: "Trusted", criterion: "Done")
    write(GRAPH, graph_text(nodes: [node_hash("n9")]))
    before = node_rows
    plan = sync_up_plan

    assert_equal [GRAPH], plan.conflicts
    assert_empty plan.taking(:read)
    assert_equal before, node_rows
  end

  def test_an_emptied_graph_file_is_read_back_and_empties_the_rows
    printed_node("Emptied")
    write(GRAPH, graph_text)
    sync.apply(sync_up_plan)

    assert_empty node_rows
  end

  def reader = Plastic::Graph::Knowledge::Reader.new(folder, { "1" => retrieval.intent("1") }, retrieval.origin_id)

  def test_the_reader_applies_a_graph_file_it_is_given
    write(GRAPH, graph_text(nodes: [node_hash("n1")]))
    read = reader.read(GRAPH)
    apply_read(read)

    assert_equal %i[work], [read.database]
    assert_equal ["n1"], node_rows.map { |row| row[:id] }
  end
end

class KnowledgeReaderGraphViewInvalidTest < Plastic::TestCase
  include GraphFileHelpers

  fixtures :alpha_synced

  def refused_message(text)
    node = printed_node("Trusted")
    write(GRAPH, text)
    message = assert_raises(Plastic::Invalid) { sync.apply(sync_up_plan) }.message

    assert_equal [node.id], node_rows.map { |row| row[:id] }
    message
  end

  def test_an_edge_to_a_node_the_file_does_not_hold_is_refused_and_writes_no_row
    message = refused_message(graph_text(nodes: [node_hash("n1")], edges: [edge_hash("n1", "n5")]))

    assert_includes message, GRAPH
    assert_includes message, "n5"
  end

  def test_a_node_in_an_unknown_state_is_refused_and_writes_no_row
    message = refused_message(graph_text(nodes: [node_hash("n1", state: "flying")]))

    assert_includes message, GRAPH
    assert_includes message, "flying"
  end

  def test_an_approval_that_is_a_string_is_refused_and_writes_no_row
    message = refused_message(graph_text(nodes: [node_hash("n1")], approval: "yes"))

    assert_includes message, GRAPH
    assert_includes message, "approval"
  end

  def test_a_graph_file_that_names_another_intent_is_refused
    message = refused_message(graph_text(nodes: [node_hash("n1")]).sub('"intent": "1"', '"intent": "2"'))

    assert_includes message, GRAPH
  end
end

class KnowledgeReaderGraphViewRestoreTest < Plastic::TestCase
  include GraphFileHelpers

  fixtures :alpha_synced

  def printed_node_ids = JSON.parse(folder.read(GRAPH)).fetch("nodes").map { |row| row.fetch("id") }

  def test_sync_down_regenerates_from_rows_after_a_tampered_view
    node = store_graphs.work.add_node(intent_id: "1", title: "Trusted", criterion: "Done")
    write(GRAPH, "not even JSON")

    sync.apply(sync.plan(:down, overwrite: nil))

    assert_equal [node.id], printed_node_ids
  end
end
