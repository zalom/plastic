# frozen_string_literal: true

require_relative "../../test_helper"

class PrintsTest < Plastic::TestCase
  FIELDS = %w[intent_id origin_id parent_id ref slug title kind status disposition opened_at closed_at].freeze

  def index_text = Plastic::Graph::Prints.index(store_graphs.retrieval).text

  def test_index_json_lists_intents_in_luhmann_order_with_every_field
    work = store_graphs.work
    %w[One Two].each { |title| work.write_intent(title:) }
    work.write_intent(title: "Child", parent_id: "1")
    index = JSON.parse(index_text)
    intents = index["intents"]

    assert_equal %w[1 1a 2], intents.map { |intent| intent["intent_id"] }
    assert_equal [FIELDS, "global"], [intents.first.keys, index["store"]]
  end

  def test_clusters_list_their_intents
    store_graphs.work.write_intent(title: "One")
    store_graphs.databases[:work].transaction { |batch| batch.put(:clusters, { name: "Core", intent_id: "1" }) }

    assert_equal [{ "name" => "Core", "intents" => ["1"] }], JSON.parse(index_text)["clusters"]
  end

  def test_the_same_rows_print_the_same_bytes
    store_graphs.work.write_intent(title: "One")

    assert_equal index_text, index_text
  end

  def test_every_printed_file_has_its_hash_recorded
    graphs = store_graphs
    graphs.work.write_intent(title: "One")
    graphs.work.print_intent("1")
    printed = store_graphs.retrieval.printed

    %w[store/index.json store/1--one/intent.md store/1--one/graph.json store/1--one/savepoint.md].each do |path|
      assert_equal Digest::SHA256.file(store_path(path)).hexdigest, printed.fetch(path)
    end
  end
  Print = Plastic::Graph::Prints::Print

  def test_a_text_print_hashes_its_text_and_compares_with_the_record
    print = Print.text("a.md", :knowledge, "x\n")
    sha = Digest::SHA256.hexdigest("x\n")

    assert_equal [sha, "x\n", true, false], [print.sha256, print.text, print.recorded?({ "a.md" => sha }), print.recorded?({})]
    assert_equal %i[path sha256 at], print.printed_row.keys
  end

  def test_a_print_is_level_once_written
    print = Print.text("a.md", :knowledge, "x\n")

    refute print.level?(folder)
    print.write_to(folder)

    assert print.level?(folder)
  end

  def test_an_intent_with_no_savepoint_lines_prints_no_savepoint_file
    store_graphs.work.write_intent(title: "One")
    store_graphs.databases[:work].transaction { |batch| batch.remove(:savepoints, intent_id: "1") }

    assert_equal %w[store/1--one/intent.md store/1--one/graph.json],
      Plastic::Graph::Prints.of_intent(retrieval, retrieval.intent("1")).map(&:path)
  end

  def test_the_graph_file_lists_nodes_and_edges_without_the_origin
    store_graphs.work.write_intent(title: "One")
    store_graphs.databases[:work].transaction { |batch| batch.put(:edges, { intent_id: "1", from: "a", to: "b", kind: "needs" }) }
    graph = JSON.parse(Plastic::Graph::Prints.of_intent(retrieval, retrieval.intent("1")).last.text)

    assert_equal({ "intent" => "1", "approval" => nil, "verdicts" => [], "nodes" => [], "edges" => [{ "intent_id" => "1", "from" => "a", "to" => "b", "kind" => "needs" }] }, graph)
  end

  def test_a_kept_file_print_reads_its_bytes_only_to_write
    row = { name: "store/1--one/x.bin", mode: 0o100644, mtime: 0, sz: 1, data: Plastic::Graph::SQL::Bytes.new("z"), intent_id: "1",
            sha256: "h" }
    store_graphs.databases[:references].transaction { |batch| batch.put(:sqlar, row) }
    print = Plastic::Graph::Prints.kept_files(retrieval, retrieval.kept_files("1")).first

    assert_equal ["store/1--one/x.bin", :references, "h", "z"], [print.path, print.database, print.sha256, print.text]
  end

  def test_the_store_prints_the_index_first_then_each_intent
    open_intent("One")
    open_intent("Two")

    assert_equal %w[store/index.json store/1--one/intent.md store/1--one/savepoint.md store/1--one/graph.json store/2--two/intent.md
      store/2--two/savepoint.md store/2--two/graph.json], Plastic::Graph::Prints.of_store(retrieval).map(&:path)
  end

  def test_index_json_names_the_store_and_origin_and_ends_with_a_newline
    text = index_text

    assert_equal [{ "store" => "global", "origin_id" => origin, "intents" => [], "clusters" => [] }, "\n"], [JSON.parse(text), text[-1]]
  end

  def test_the_savepoint_file_holds_one_line_per_row
    store_graphs.work.write_intent(title: "One")
    savepoint = Plastic::Graph::Prints.of_intent(retrieval, retrieval.intent("1"))[1]

    assert_equal ["store/1--one/savepoint.md", "#{retrieval.savepoints("1").first.line}\n"], [savepoint.path, savepoint.text]
  end

  def graph_text_with_node
    store_graphs.work.write_intent(title: "One")
    store_graphs.databases[:work].transaction { |batch| batch.put(:nodes, { intent_id: "1", id: "n1", kind: "build" }) }
    Plastic::Graph::Prints.of_intent(retrieval, retrieval.intent("1")).last.text
  end

  def test_the_graph_file_lists_each_node_and_ends_with_a_newline
    text = graph_text_with_node

    assert_equal [["n1"], "\n"], [JSON.parse(text)["nodes"].map { |node| node["id"] }, text[-1]]
  end
  def test_the_graph_file_carries_the_approval_the_verdicts_and_each_nodes_criterion
    store_graphs.work.write_intent(title: "One")
    store_graphs.databases[:work].transaction do |batch|
      batch.add("INSERT INTO approvals(intent_id, origin_id, at, session_id) VALUES ('1', :origin, '2026-10-05T10:00:00+02:00', 's')", origin:)
      batch.add("INSERT INTO verdicts(intent_id, round, origin_id, verdict, findings, at, session_id) VALUES ('1', 1, :origin, 'accept', 'ok', '2026-10-05T11:00:00+02:00', 's')", origin:)
    end
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "works")
    graph = JSON.parse(Plastic::Graph::Prints.of_intent(retrieval, retrieval.intent("1")).last.text)

    assert_equal ["1", "accept", "works"], [graph.dig("approval", "intent_id"), graph.dig("verdicts", 0, "verdict"), graph.dig("nodes", 0, "criterion")]
  end

  def test_a_context_row_prints_context_json_into_the_intent_folder_and_no_row_prints_none
    store_graphs.work.write_intent(title: "One")
    paths = ->{ Plastic::Graph::Prints.of_intent(retrieval, retrieval.intent("1")).map(&:path) }
    refute_includes paths.call, "store/1--one/context.json"
    store_graphs.databases[:knowledge].transaction do |batch|
      batch.put(:retrieval_contexts, { intent_id: "1", data: JSON.generate("evidence" => []), updated_at: "2026-10-05T10:00:00+02:00" })
    end

    assert_includes paths.call, "store/1--one/context.json"
  end
end
