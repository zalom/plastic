# frozen_string_literal: true

require_relative "../../test_helper"

# The knowledge file owns the intent and its closing rows; the work file keeps the nodes, the edges, the runs, the roadmaps and the work log.
class KnowledgeOwnsIntentTest < Plastic::TestCase
  fixtures :empty

  MOVED = %w[intents clusters completions approvals verdicts archives archive_entries work_log_pending].freeze

  def graphs(session = "s-1") = Plastic::Graph.open(home: @plastic_home, store: "global", session:)

  def work = graphs.work

  def tables(key) = graphs.databases.fetch(key).rows("SELECT name FROM sqlite_master WHERE type = 'table'").map { |row| row["name"] }

  def test_a_new_store_holds_the_moved_tables_in_knowledge_and_none_in_work
    assert_equal MOVED, MOVED & tables(:knowledge)
    assert_empty MOVED & tables(:work)
    assert_equal %w[edges nodes roadmaps runs work_log], %w[edges nodes roadmaps runs work_log] & tables(:work)
  end

  def test_a_new_intent_is_one_knowledge_row_and_a_work_log_line_in_work
    work.write_intent(title: "Alpha")

    assert_equal ["Alpha"], graphs.databases.fetch(:knowledge).rows("SELECT title FROM intents").map { |row| row["title"] }
    assert_equal ["opened"], graphs.databases.fetch(:work).rows("SELECT kind FROM work_log").map { |row| row["kind"] }
  end

  def test_the_go_ahead_and_the_cluster_rows_are_knowledge_rows
    work.write_intent(title: "Alpha")
    work.approve_intent("1")

    assert_equal 1, graphs.databases.fetch(:knowledge).row("SELECT count(*) AS n FROM approvals").fetch("n")
  end

  def test_an_intent_with_a_node_reads_back_through_the_graph_from_both_files
    work.write_intent(title: "Alpha")
    work.add_node(intent_id: "1", id: "n1", kind: "task", title: "First")

    assert_equal ["Alpha", ["n1"]], [graphs.retrieval.intent("1").title, graphs.retrieval.nodes("1").map(&:id)]
  end

  def test_the_graph_file_prints_from_both_files_and_reads_back_into_both
    work.write_intent(title: "Alpha")
    work.approve_intent("1")
    work.add_node(intent_id: "1", id: "n1", kind: "task", title: "First")
    work.print_intent("1")
    text = File.read(Dir.glob(File.join(@plastic_home, "stores", "global", "store", "1--*", "graph.json")).first)
    reread = JSON.parse(text)

    assert_equal [true, ["n1"]], [!reread.fetch("approval").nil?, reread.fetch("nodes").map { |node| node.fetch("id") }]
  end
end
