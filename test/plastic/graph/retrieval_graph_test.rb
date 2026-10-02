# frozen_string_literal: true

require_relative "../../test_helper"

class RetrievalGraphTest < Plastic::TestCase
  def put(key, table, row) = store_graphs.databases[key].transaction { |batch| batch.put(table, row) }

  def test_the_origin_id_is_the_installation_id
    assert_equal [origin, "global"], [retrieval.origin_id, retrieval.store]
  end

  def test_intents_read_in_luhmann_order
    work = store_graphs.work
    %w[One Two].each { |title| work.write_intent(title:) }
    work.write_intent(title: "Child", parent_id: "1")

    assert_equal %w[1 1a 2], retrieval.intents.map(&:intent_id)
    assert_equal ["Child", nil], [retrieval.intent("1a").title, retrieval.intent("9")]
  end

  def test_rows_of_another_origin_stay_out
    put(:work, :intents, { intent_id: "1", origin_id: "beef", slug: "a", title: "A", status: "open" })

    assert_empty retrieval.intents
  end

  def test_a_read_with_an_intent_id_reads_that_intent_alone
    %w[One Two].each { |title| store_graphs.work.write_intent(title:) }
    read = retrieval

    assert_equal [%w[1 2], ["2"], ["2--two.md"]], [read.savepoints.map(&:intent_id), read.savepoints("2").map(&:intent_id),
      read.documents("2").map(&:path)]
  end

  def test_clusters_nodes_and_edges_read_back
    put(:work, :clusters, { name: "Core", intent_id: "1" })
    put(:work, :nodes, { intent_id: "1", id: "n1", kind: "build" })
    put(:work, :edges, { intent_id: "1", from: "n1", to: "n2", kind: "needs" })

    assert_equal [["Core"], ["n1"], ["n2"]], [retrieval.clusters.map(&:name), retrieval.nodes.map(&:id), retrieval.edges("1").map(&:to)]
  end

  def test_a_kept_file_reads_without_its_bytes_and_its_bytes_read_by_name
    row = { name: "store/1--a/x.bin", mode: 0o100644, mtime: 0, sz: 2, data: Plastic::Graph::SQL::Bytes.new("\x00\xFF".b),
            intent_id: "1", sha256: "h" }
    put(:references, :sqlar, row)

    assert_equal [["store/1--a/x.bin", "h"]], retrieval.kept_files("1").map { |file| [file.name, file.sha256] }
    assert_equal "\x00\xFF".b, retrieval.kept_file_data("store/1--a/x.bin")
  end

  def test_printed_maps_each_path_to_its_hash_across_the_databases
    put(:work, :printed, { path: "store/index.json", sha256: "a", at: "t" })
    put(:knowledge, :printed, { path: "store/1--a/spec.md", sha256: "b", at: "t" })

    assert_equal({ "store/index.json" => "a", "store/1--a/spec.md" => "b" }, retrieval.printed)
  end

  def test_searches_indexed_passages_without_matching_an_intent_title
    intent = open_intent("Unrelated")
    path = "#{intent.dir}/research.txt"
    write(path, "The retrieval evidence stays searchable.\n")
    apply_read(Plastic::Graph::Reader.new(folder, { intent.intent_id => intent }, origin, retrieval:).read(path))

    result = retrieval.search("retrieval evidence")

    assert_equal [[intent.intent_id, "research.txt", "The retrieval evidence stays searchable.\n", 1]],
      result.map { |row| row.values_at("intent_id", "path", "body", "position") }
  end

  def test_backfills_a_text_reference_once_without_removing_its_attachment
    row = { name: "store/1--alpha/research.txt", mode: 0o100644, mtime: 0, sz: 18,
            data: Plastic::Graph::SQL::Bytes.new("Archived evidence\n"), intent_id: "1", sha256: "source" }
    put(:references, :sqlar, row)

    2.times { retrieval.backfill! }

    assert_equal [["research.txt", "Archived evidence\n"]], retrieval.search("archived evidence").map { |found| found.values_at("path", "body") }
    assert_equal "Archived evidence\n", retrieval.kept_file_data(row[:name])
  end
end
