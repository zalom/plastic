# frozen_string_literal: true

require_relative "../../support/kernel"

class IntentFileTest < Minitest::Test
  include KernelFixtures::StoreGraphs

  DIR = "store/1--alpha"
  AT = "2026-10-01T10:00:00+02:00"
  GRAPH = { "nodes" => [{ "id" => "n1", "kind" => "build", "state" => "open", "origin_id" => "x" }],
            "edges" => [{ "from" => "n1", "to" => "n2", "kind" => "needs" }] }.freeze

  def setup
    super
    open_intent
  end

  # Writes the file, reads it into rows, and returns the database its rows went to.
  def read_in(rel, bytes)
    write("#{DIR}/#{rel}", bytes)
    read = Plastic::Graph::Reader.new(folder, { "1" => retrieval.intent("1") }, origin).read("#{DIR}/#{rel}")
    apply_read(read)
    read.database
  end

  def kept(name) = retrieval.kept_files("1").find { |file| file.name == "#{DIR}/#{name}" }

  def test_graph_json_reads_into_nodes_and_edges
    assert_equal :work, read_in("graph.json", JSON.generate(GRAPH))
    assert_equal [%w[n1 build open], [%w[n1 n2 needs]]],
      [retrieval.nodes("1").first.to_h.values_at(:id, :kind, :state), retrieval.edges("1").map { |e| [e.from, e.to, e.kind] }]
  end

  def test_a_second_graph_json_replaces_the_first
    read_in("graph.json", JSON.generate(GRAPH))
    read_in("graph.json", JSON.generate({ "nodes" => [{ "id" => "n9" }] }))

    assert_equal [["n9"], []], [retrieval.nodes("1").map(&:id), retrieval.edges("1")]
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

  def test_any_other_file_is_kept_whole
    assert_equal :references, read_in("x.bin", "\x00\xFF".b)
    file = kept("x.bin")

    assert_equal [0o100644, 2, Digest::SHA256.hexdigest("\x00\xFF".b)], [file.mode, file.sz, file.sha256]
    assert_equal "\x00\xFF".b, retrieval.kept_file_data(file.name)
  end

  def test_markdown_under_resources_and_bytes_that_are_not_text_are_kept
    assert_equal %i[references references], [read_in("resources/notes.md", "# Notes\n"), read_in("odd.md", "\xFF".b)]
    assert_equal [true, true], [!kept("resources/notes.md").nil?, !kept("odd.md").nil?]
  end
end
