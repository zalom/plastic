# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeReaderIntentFileTest < Plastic::TestCase
  fixtures :alpha

  DIR = "store/1--alpha"
  AT = "2026-10-01T10:00:00+02:00"
  GRAPH = { "nodes" => [{ "id" => "n1", "kind" => "build", "state" => "open", "origin_id" => "x" }],
            "edges" => [{ "from" => "n1", "to" => "n2", "kind" => "needs" }] }.freeze

  # Writes the file, reads it into rows, and returns the database its rows went to.
  def read_in(rel, bytes)
    write("#{DIR}/#{rel}", bytes)
    read = Plastic::Graph::Knowledge::Reader.new(folder, { "1" => retrieval.intent("1") }, origin).read("#{DIR}/#{rel}")
    apply_read(read)
    read.database
  end

  def kept(name) = retrieval.kept_files("1").find { |file| file.name == "#{DIR}/#{name}" }

  def test_graph_json_cannot_replace_node_or_edge_rows
    node = store_graphs.work.add_node(intent_id: "1", title: "Recorded", criterion: "Done")

    assert_raises(Plastic::Invalid) { read_in("graph.json", JSON.generate(GRAPH)) }
    assert_equal [node.id], retrieval.nodes("1").map(&:id)
  end

  def test_savepoint_md_reads_one_row_per_line
    assert_equal :work, read_in("savepoint.md", "#{AT}  Spec written\nfree text\n")
    assert_equal [[1, AT, "Spec written"], [2, nil, "free text"]],
      retrieval.savepoints("1").map { |line| line.to_h.values_at(:position, :at, :text) }
  end

  def test_a_markdown_file_reads_into_a_document
    assert_equal :knowledge, read_in("plan.md", "# Plan\n")
    assert_equal "# Plan\n", retrieval.documents("1").find { |document| document.path == "plan.md" }.body
  end

  def test_a_document_write_keeps_an_immutable_revision_head_passage_and_fts_row
    read_in("plan.md", "# Retrieval\n\nIndexed evidence\n")

    row = store_graphs.databases.fetch(:knowledge).row("SELECT body, sha256, position FROM document_fts WHERE document_fts MATCH 'evidence'")

    assert_equal ["# Retrieval\n\nIndexed evidence\n", Digest::SHA256.hexdigest("# Retrieval\n\nIndexed evidence\n"), 1],
      row.values_at("body", "sha256", "position")
  end

  def attributed_savepoint
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.put(:savepoints, { intent_id: "1", position: 1, at: AT, text: "Original", session_id: "owner" })
    end
  end

  def test_sync_preserves_attribution_only_for_existing_savepoint_lines
    attributed_savepoint
    write("#{DIR}/savepoint.md", "new line\n#{AT}  Original\n#{AT}  Original\n")
    Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases).read(["#{DIR}/savepoint.md"])

    assert_equal [nil, "owner", nil], retrieval.savepoints("1").map(&:session_id)
    assert_equal ["1"], retrieval.touched("owner")
  end

  def test_any_other_file_is_kept_whole
    assert_equal :references, read_in("x.bin", "\x00\xFF".b)
    file = kept("x.bin")

    assert_equal [0o100644, 2, Digest::SHA256.hexdigest("\x00\xFF".b)], [file.mode, file.sz, file.sha256]
    assert_equal "\x00\xFF".b, retrieval.kept_file_data(file.name)
  end

  def test_every_valid_utf8_reference_without_a_nul_is_a_document
    assert_equal %i[knowledge references knowledge knowledge], [read_in("resources/notes.md", "# Notes\n"), read_in("odd.md", "\xFF".b),
      read_in("notes.txt", "plain text\n"), read_in("data.json", '{"topic":"retrieval"}')]

    assert_equal ["1--alpha.md", "data.json", "notes.txt", "resources/notes.md"], retrieval.documents("1").map(&:path).sort
    assert_equal [true], [!kept("odd.md").nil?]
  end
end
