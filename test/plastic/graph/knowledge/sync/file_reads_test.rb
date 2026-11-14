# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeSyncFileReadsTest < Plastic::TestCase
  fixtures :alpha

  DIR = "store/1--alpha"

  def sync_read(*names)
    names.each { |name| write("#{DIR}/#{name}", "# #{name}\n") }
    Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases).read(names.map { |name| "#{DIR}/#{name}" })
  end

  def fts(sql) = store_graphs.databases.fetch(:knowledge).rows(sql).map { |row| row.fetch("body") }

  def test_a_first_sync_of_documents_makes_them_searchable
    sync_read("notes.md", "other.md")

    assert_equal ["# other.md\n"], fts("SELECT body FROM document_fts WHERE document_fts MATCH 'other'")
    assert_equal ["# notes.md\n"], fts("SELECT body FROM document_fts WHERE path = 'notes.md'")
  end

  GRAPH = "#{DIR}/graph.json"

  def file_reads = Plastic::Graph::Knowledge::Sync::FileReads.new(folder:, retrieval:, databases: store_graphs.databases, printer: Plastic::Graph::Printer.new(folder, store_graphs.databases, retrieval))

  def write_null_id_graph
    graph = JSON.parse(folder.read(GRAPH))
    write(GRAPH, "#{JSON.pretty_generate(graph.merge("nodes" => [{ "id" => nil, "state" => "open", "title" => "T" }]))}\n")
  end

  def test_a_read_the_database_refuses_is_returned_as_unreadable_and_writes_no_row
    write_null_id_graph
    write("#{DIR}/notes.md", "# notes\n")

    assert_equal ["read #{DIR}/notes.md"], file_reads.call([GRAPH, "#{DIR}/notes.md"])
    assert_empty store_graphs.databases.fetch(:work).rows("SELECT id FROM nodes")
  end

  def rename_by_hand_in_the_index
    index = JSON.parse(folder.read("store/index.json"))
    index.fetch("intents").each { |entry| entry["title"] = "Renamed by hand" }
    write("store/index.json", JSON.pretty_generate(index))
  end

  def test_in_one_group_the_read_the_database_refuses_leaves_the_good_read_written
    write_null_id_graph
    rename_by_hand_in_the_index
    lines = file_reads.call([GRAPH, "store/index.json"])

    assert_equal ["read store/index.json"], lines
    assert_equal "Renamed by hand", retrieval.intent("1").title
  end

  def test_in_one_group_the_read_the_database_refuses_writes_no_row
    write_null_id_graph
    rename_by_hand_in_the_index
    file_reads.call([GRAPH, "store/index.json"])

    assert_empty store_graphs.databases.fetch(:work).rows("SELECT id FROM nodes")
  end

  def test_a_read_the_reader_refuses_leaves_the_other_reads_written
    write(GRAPH, "{\"hand\":true}")
    write("#{DIR}/notes.md", "# notes\n")

    assert_equal ["read #{DIR}/notes.md"], file_reads.call([GRAPH, "#{DIR}/notes.md"])
  end

  def test_a_read_the_database_refuses_stays_hand_edited_and_is_listed_by_the_next_plan
    write_null_id_graph
    file_reads.call([GRAPH])
    plan = Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases).plan(:up)

    assert_equal [GRAPH], plan.unreadable_files.keys
  end

  def test_a_second_sync_of_a_changed_document_replaces_its_search_rows
    sync_read("notes.md")
    write("#{DIR}/notes.md", "# changed words\n")
    Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases).read(["#{DIR}/notes.md"])

    assert_equal ["# changed words\n"], fts("SELECT body FROM document_fts WHERE path = 'notes.md'")
  end
end
