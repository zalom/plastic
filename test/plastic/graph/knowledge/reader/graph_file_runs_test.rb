# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "graph_file_test"

# A graph.json prints each node's holder and each run, and still reads an old file with `by` and `retries`.
class KnowledgeReaderGraphFileRunsTest < Plastic::TestCase
  include GraphFileHelpers

  fixtures :alpha_synced

  def import(*nodes)
    write(GRAPH, graph_text(nodes:))
    sync.apply(sync_up_plan)
  end

  def runs = retrieval.runs("1").map { |run| run.to_h.values_at(:node_id, :number, :agent, :session_id, :started_at, :ended_at, :result) }

  def test_an_old_file_with_by_and_retries_has_no_problem
    assert_empty Plastic::Graph::Knowledge::Reader::GraphFile.new(graph_text(nodes: [node_hash("n1")]), "1", nil, GRAPH).problems
  end

  def test_an_old_done_node_imports_with_one_closed_run
    import(node_hash("n1"))

    assert_equal [["n1", 1, "", "agent-7", "2026-10-20T08:00:00Z", "2026-10-20T08:00:00Z", "done"]], runs
  end

  def test_an_old_claimed_node_imports_with_its_claim_and_an_open_run
    import(node_hash("n1", state: "claimed", by: "s-4"))

    assert_equal [["s-4", "2026-10-20T08:00:00Z"], [["n1", 1, "", "s-4", "2026-10-20T08:00:00Z", nil, nil]]],
      [retrieval.node("1", "n1").to_h.values_at(:claimed_by, :claimed_at), runs]
  end

  def test_an_old_node_with_no_holder_imports_with_no_run
    import(node_hash("n1", state: "open", by: nil, retries: 0))

    assert_empty runs
  end

  def test_a_node_of_the_new_form_imports_with_its_runs
    node = node_hash("n1").except("by", "retries").merge("claimed_by" => nil, "claimed_at" => nil, "seen_at" => nil)
    run = { "intent_id" => "1", "node_id" => "n1", "number" => 1, "agent" => "plastic-executor", "session_id" => "s-1",
            "started_at" => "2026-10-20T07:00:00Z", "ended_at" => "2026-10-20T08:00:00Z", "result" => "done" }
    write(GRAPH, "#{JSON.pretty_generate({ "intent" => "1", "nodes" => [node], "runs" => [run], "edges" => [], "verdicts" => [] })}\n")
    sync.apply(sync_up_plan)

    assert_equal [["n1", 1, "plastic-executor", "s-1", "2026-10-20T07:00:00Z", "2026-10-20T08:00:00Z", "done"]], runs
  end

  def test_the_printed_file_holds_the_holder_and_each_run
    work = store_graphs.work
    node = work.add_node(intent_id: "1", title: "Build", criterion: "Done")
    work.claim_node(intent_id: "1", id: node.id, by: "s-1")
    work.print_intent("1")
    printed = JSON.parse(File.read(File.join(store_root, "store/1--alpha/graph.json")))

    assert_equal ["s-1", ["s-1"]], [printed["nodes"].first["claimed_by"], printed["runs"].map { |run| run["session_id"] }]
    refute_includes printed["nodes"].first.keys, "by"
    refute_includes printed["nodes"].first.keys, "retries"
  end
end
