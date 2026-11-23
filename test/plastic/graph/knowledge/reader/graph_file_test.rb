# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeReaderGraphFileTest < Plastic::TestCase
  GraphFile = Plastic::Graph::Knowledge::Reader::GraphFile
  PATH = "store/1--alpha/graph.json"

  def problems(data) = GraphFile.new(data.is_a?(String) ? data : JSON.generate({ "intent" => "1" }.merge(data)), "1", nil, PATH).problems

  def test_a_file_that_is_no_json_names_the_parse_error
    assert_equal 1, problems("{not json").size
    assert_includes problems("{not json").first, "#{PATH} is not valid JSON: "
  end

  def test_a_file_whose_json_is_not_an_object_is_refused
    assert_equal ["#{PATH} is not valid JSON: it is not an object"], problems("[1, 2]")
  end

  def test_a_file_that_holds_nothing_but_its_intent_has_no_problem
    assert_empty problems({})
  end

  def test_a_node_that_is_not_an_object_is_refused
    assert_equal ["#{PATH} holds a node that is not an object"], problems("nodes" => ["n1"])
  end

  def test_an_edge_that_is_a_bare_name_must_name_a_node
    assert_equal ["#{PATH} holds an edge to \"n5\", which is no node it holds"], problems("edges" => ["n5"])
  end

  def test_an_edge_between_the_nodes_of_the_file_is_accepted
    nodes = [{ "id" => "n1", "state" => "done" }, { "id" => "n2", "state" => "done" }]

    assert_empty problems("nodes" => nodes, "edges" => [{ "from" => "n1", "to" => "n2" }])
  end

  def test_a_file_that_names_no_intent_says_so_in_words
    text = JSON.generate({})

    assert_equal ["#{PATH} names no intent, not 1"], GraphFile.new(text, "1", nil, PATH).problems
  end

  def test_a_file_that_names_another_intent_quotes_it
    text = JSON.generate({ "intent" => "2" })

    assert_equal ["#{PATH} names intent \"2\", not 1"], GraphFile.new(text, "1", nil, PATH).problems
  end

  def test_a_node_with_no_state_says_so_in_words
    assert_equal ["#{PATH} holds node \"n1\" with no state"], problems("nodes" => [{ "id" => "n1" }])
  end

  def test_a_node_in_an_unknown_state_names_the_state
    assert_equal ["#{PATH} holds node \"n1\" in the unknown state \"stuck\""], problems("nodes" => [{ "id" => "n1", "state" => "stuck" }])
  end

  def test_an_edge_with_no_end_says_so_in_words
    nodes = [{ "id" => "n1", "state" => "done" }]

    assert_equal ["#{PATH} holds an edge with no end"], problems("nodes" => nodes, "edges" => [{ "from" => "n1" }])
  end

  def test_a_verdict_that_is_not_an_object_is_refused
    assert_equal ["#{PATH} holds the verdict \"accept\""], problems("verdicts" => ["accept"])
  end

  def test_a_verdict_outside_the_known_verdicts_is_refused
    assert_equal 1, problems("verdicts" => [{ "verdict" => "maybe" }]).size
  end

  def test_an_approval_with_an_unknown_field_is_refused
    assert_equal ["#{PATH} holds the unknown field mood in approvals"], problems("approval" => { "mood" => "good" })
  end

  def test_an_entry_that_is_not_an_object_has_no_unknown_field
    assert_empty problems("verdicts" => []).grep(/unknown field/)
  end
end

class KnowledgeReaderGraphCompletionTest < Plastic::TestCase
  GRAPH = "store/1--alpha/graph.json"
  GraphFile = Plastic::Graph::Knowledge::Reader::GraphFile

  fixtures :alpha_synced

  def completion_hash(**fields)
    { "intent_id" => "1", "at" => "2026-10-20T09:00:00Z", "session_id" => "s1", "judge" => "verdict",
      "criteria" => "{}", "evidence" => "{}", "outcome_sha256" => "abc" }.merge(fields.transform_keys(&:to_s))
  end

  def graph_text(**parts) = "#{JSON.pretty_generate({ "intent" => "1" }.merge(parts.transform_keys(&:to_s)))}\n"

  def sync = Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases)

  def read_up = sync.apply(sync.plan(:up))

  def put_completion
    store_graphs.databases.fetch(:store).transaction do |batch|
      batch.put(:completions, { intent_id: "1", origin_id: retrieval.origin_id, at: "2026-10-19T09:00:00Z", session_id: "s0", judge: "verdict",
                                criteria: "{}", evidence: "{}", outcome_sha256: "kept" })
    end
  end

  def test_a_completion_in_the_file_is_read_into_a_row_with_the_local_origin
    write(GRAPH, graph_text(completion: completion_hash))
    read_up

    assert_equal [["1", "s1", retrieval.origin_id]], store_graphs.databases.fetch(:store).rows("SELECT intent_id, session_id, origin_id FROM completions").map(&:values)
  end

  def test_a_file_without_the_completion_key_leaves_the_row_the_intent_held
    put_completion
    write(GRAPH, graph_text)
    read_up

    assert_equal ["kept"], store_graphs.databases.fetch(:store).rows("SELECT outcome_sha256 FROM completions").map { |row| row["outcome_sha256"] }
  end

  def test_a_null_completion_leaves_the_row_the_intent_held
    put_completion
    write(GRAPH, graph_text(completion: nil))
    read_up

    assert_equal 1, store_graphs.databases.fetch(:store).rows("SELECT * FROM completions").size
  end

  def test_a_completion_that_names_another_intent_is_refused
    text = graph_text(completion: completion_hash(intent_id: "2"))

    assert_equal ["#{GRAPH} holds a completion of intent \"2\", not 1"], GraphFile.new(text, "1", nil, GRAPH).problems
  end

  def test_a_completion_that_is_not_an_object_is_refused
    text = graph_text(completion: "done")

    assert_equal ["#{GRAPH} holds a completion that is not an object"], GraphFile.new(text, "1", nil, GRAPH).problems
  end

  def test_a_completion_with_an_unknown_field_is_refused
    text = graph_text(completion: completion_hash(colour: "red"))

    assert_equal ["#{GRAPH} holds the unknown field colour in completions"], GraphFile.new(text, "1", nil, GRAPH).problems
  end
end

module GraphFileHelpers
  GRAPH = "store/1--alpha/graph.json"

  def node_hash(id, **fields)
    { "intent_id" => "1", "id" => id, "kind" => "work", "title" => "Node #{id}", "criterion" => nil, "state" => "done",
      "by" => "agent-7", "input" => nil, "output" => nil, "question" => nil, "answer" => nil, "reason" => nil,
      "findings" => "checked", "retries" => 2, "updated_at" => "2026-10-20T08:00:00Z" }
      .merge(fields.transform_keys(&:to_s))
  end

  def edge_hash(from, to) = { "intent_id" => "1", "from" => from, "to" => to, "kind" => "needs" }

  def graph_text(nodes: [], edges: [], approval: nil, verdicts: [])
    "#{JSON.pretty_generate({ "intent" => "1", "approval" => approval, "verdicts" => verdicts, "nodes" => nodes, "edges" => edges })}\n"
  end

  def sync = (@sync ||= Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases))

  def sync_up_plan = sync.plan(:up)

  def node_rows = structure.nodes("1").map(&:to_h)

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

    assert_equal [["n1", "done", "2026-10-20T08:00:00Z", retrieval.origin_id]],
      node_rows.map { |row| row.values_at(:id, :state, :updated_at, :origin_id) }
  end

  def test_sync_up_stores_the_times_of_a_graph_json_written_with_an_offset_in_utc
    write(GRAPH, graph_text(nodes: [node_hash("n1", updated_at: "2026-10-20T10:00:00+02:00")]))
    sync.apply(sync_up_plan)

    assert_equal [["2026-10-20T08:00:00Z"], [["2026-10-20T08:00:00Z", "2026-10-20T08:00:00Z"]]],
      [node_rows.map { |row| row[:updated_at] }, structure.runs("1").map { |run| [run.started_at, run.ended_at] }]
  end

  def test_sync_up_reads_the_runs_of_a_hand_edited_graph_json
    write(GRAPH, graph_text(nodes: [node_hash("n1")]))
    sync.apply(sync_up_plan)

    assert_equal [["n1", 1, "agent-7", "done"]], structure.runs("1").map { |run| [run.node_id, run.number, run.session_id, run.result] }
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

    assert_equal [["n1", "n2", "needs"]], structure.edges("1").map { |edge| edge.to_h.values_at(:from, :to, :kind) }
    assert_equal "2026-10-20T09:00:00Z", structure.approvals("1").first.at
  end

  def test_the_verdicts_are_read_with_the_nodes
    write_full_graph
    sync.apply(sync_up_plan)

    assert_equal [[1, "accept"]], structure.verdicts("1").map { |row| row.to_h.values_at(:round, :verdict) }
  end

  def file_and_print = [folder.read(GRAPH), retrieval.stored.printed[GRAPH]]

  def test_a_second_sync_up_leaves_the_file_bytes_and_the_printed_hash_as_they_are
    write(GRAPH, graph_text(nodes: [node_hash("n1")]))
    sync.apply(sync_up_plan)
    before = file_and_print
    again = sync_up_plan

    assert_empty again.entries_for(:read)
    sync.apply(again)

    assert_equal before, file_and_print
  end

  def test_a_file_and_rows_both_changed_since_the_print_are_a_conflict_and_nothing_is_written
    store_graphs.work.add_node(intent_id: "1", title: "Trusted", criterion: "Done")
    write(GRAPH, graph_text(nodes: [node_hash("n9")]))
    before = node_rows
    plan = sync_up_plan

    assert_equal [GRAPH], plan.conflicts
    assert_empty plan.entries_for(:read)
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
    read = reader.read(GRAPH, FixedClock::STAMP)
    apply_read(read)

    assert_equal ["n1"], node_rows.map { |row| row[:id] }
  end
end

class KnowledgeReaderGraphViewInvalidTest < Plastic::TestCase
  include GraphFileHelpers

  fixtures :alpha_synced

  def refused_message(text)
    node = printed_node("Trusted")
    write(GRAPH, text)
    plan = sync_up_plan
    message = plan.unreadable_files.fetch(GRAPH)
    sync.apply(plan)

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
