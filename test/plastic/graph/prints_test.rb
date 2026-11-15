# frozen_string_literal: true

require_relative "../../test_helper"

class PrintsTest < Plastic::TestCase
  FIELDS = %w[intent_id origin_id parent_id ref slug title kind status disposition reason opened_at closed_at].freeze

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

  def test_the_hand_edit_line_names_the_path_and_the_command_to_run
    assert_equal "store/index.json changed since its last print on this home, by hand or in a copy from another home; run plastic sync up first to read it into rows",
      Plastic::Graph::Prints.hand_edit_line("store/index.json")
  end

  def test_the_hand_edit_line_is_written_in_prints_only
    root = File.expand_path("../../../lib", __dir__)
    holders = Dir.glob("**/*.rb", base: root).select { |rel| File.read(File.join(root, rel)).include?("changed since its last print on this home") }

    refute_empty Dir.glob("**/*.rb", base: root)
    assert_equal ["plastic/graph/prints.rb"], holders
  end

  def test_the_guard_finds_the_phrase_in_a_sample_and_leaves_another_alone
    phrase = "changed since its last print on this home"

    assert_includes "x #{phrase} y", phrase
    refute_includes "x changed since y", phrase
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

    assert_equal({ "intent" => "1", "approval" => nil, "completion" => nil, "verdicts" => [], "nodes" => [], "edges" => [{ "intent_id" => "1", "from" => "a", "to" => "b", "kind" => "needs" }] }, graph)
  end

  def test_a_kept_file_print_reads_its_bytes_only_to_write
    row = { name: "store/1--one/x.bin", mode: 0o100644, mtime: 0, sz: 1, data: SQLite3::Blob.new("z"), intent_id: "1",
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

    assert_equal [{ "store" => "global", "origin_id" => origin, "intents" => [], "archives" => [], "clusters" => [], "links" => [] }, "\n"], [JSON.parse(text), text[-1]]
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
end

class PrintsArchiveTest < Plastic::TestCase
  def index = JSON.parse(Plastic::Graph::Prints.index(store_graphs.retrieval).text)

  def completion_row(intent_id)
    { intent_id:, origin_id: retrieval.origin_id, at: "2026-10-20T09:00:00Z", session_id: "s1", judge: "verdict",
      criteria: "{}", evidence: "{}", outcome_sha256: "abc" }
  end

  def archive(intent_id, restored_at: nil)
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.put(:completions, completion_row(intent_id))
      batch.put(:archives, { intent_id:, at: "2026-10-21T09:00:00Z", origin_id: retrieval.origin_id, restored_at:, session_id: "s2" })
    end
  end

  def graph_text(intent) = Plastic::Graph::Prints.of_intent(retrieval, intent).find { |print| print.path.end_with?("graph.json") }.text

  def test_the_graph_file_prints_the_completion_of_a_done_intent
    intent = open_intent("Alpha", status: "done")
    store_graphs.databases.fetch(:work).transaction { |batch| batch.put(:completions, completion_row("1")) }

    printed = JSON.parse(graph_text(retrieval.intent(intent.intent_id))).fetch("completion")

    assert_equal ["1", "verdict", false], [*printed.values_at("intent_id", "judge"), printed.key?("origin_id")]
  end

  def test_the_graph_file_prints_a_null_completion_when_the_intent_has_none
    intent = open_intent

    assert_nil JSON.parse(graph_text(intent)).fetch("completion")
  end

  def test_the_index_lists_an_archived_intent_among_the_intents
    open_intent("Alpha", status: "done")
    archive("1")

    assert_equal ["1"], index.fetch("intents").map { |intent| intent.fetch("intent_id") }
  end

  def test_the_index_lists_the_intents_archived_now_with_their_completion
    open_intent("Alpha", status: "done")
    archive("1")
    entry = index.fetch("archives").first

    assert_equal ["1", "2026-10-21T09:00:00Z", "s2", "verdict"], entry.values_at("intent_id", "at", "session_id").push(entry.fetch("completion").fetch("judge"))
    refute entry.fetch("completion").key?("origin_id")
  end

  def test_the_index_leaves_out_an_archive_that_was_restored
    open_intent("Alpha", status: "done")
    archive("1", restored_at: "2026-10-22T09:00:00Z")

    assert_empty index.fetch("archives")
  end

  def test_the_index_lists_no_archives_when_none_exist
    open_intent

    assert_empty index.fetch("archives")
  end

  def test_the_store_prints_no_folder_files_for_an_archived_intent
    open_intent("Alpha", status: "done")
    archive("1")
    paths = Plastic::Graph::Prints.of_store(retrieval).map(&:path)

    assert_equal ["store/index.json"], paths
  end
end

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

class PrintsLegacyTest < Plastic::TestCase
  PATH = "store/1--one/plan.md"

  def legacy_row(path, body) = { intent_id: "1", path:, body:, updated_at: STAMP }

  def put(table, row) = store_graphs.databases[:knowledge].transaction { |batch| batch.put(table, row) }

  def plan_prints = Plastic::Graph::Prints.of_intent(retrieval, retrieval.intent("1")).select { |print| print.path == PATH }

  def test_an_intent_prints_its_legacy_files_byte_for_byte
    open_intent("One")
    body = "# Plan\r\n\n  trailing  \n"
    put(:legacy_intents_data, legacy_row("plan.md", body))
    print = plan_prints.first

    assert_equal [:knowledge, body, Digest::SHA256.hexdigest(body)], [print.database, print.text, print.sha256]
  end

  def test_a_path_with_a_document_and_a_legacy_row_prints_from_the_legacy_row
    open_intent("One")
    put(:documents, { intent_id: "1", path: "plan.md", body: "from documents\n", updated_at: STAMP })
    put(:legacy_intents_data, legacy_row("plan.md", "from legacy\n"))

    assert_equal ["from legacy\n"], plan_prints.map(&:text)
  end

  def test_the_store_prints_a_path_with_both_rows_once
    open_intent("One")
    put(:documents, { intent_id: "1", path: "plan.md", body: "from documents\n", updated_at: STAMP })
    put(:legacy_intents_data, legacy_row("plan.md", "from legacy\n"))

    assert_equal 1, Plastic::Graph::Prints.of_store(retrieval).count { |print| print.path == PATH }
  end
end
