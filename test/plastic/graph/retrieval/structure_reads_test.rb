# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalStructureReadsTest < Plastic::TestCase
  def put(key, table, row) = store_graphs.databases[key].transaction { |batch| batch.put(table, row) }

  def link(from_ref, to_ref, **row) = put(:knowledge, :links, { from_ref:, to_ref:, kind: "chain", at: STAMP, **row })

  def test_nodes_and_edges_read_for_one_intent
    put(:work, :nodes, { intent_id: "1", id: "n1", kind: "build" })
    put(:work, :nodes, { intent_id: "2", id: "n2", kind: "build" })
    put(:work, :edges, { intent_id: "1", from: "n1", to: "n3", kind: "needs" })

    assert_equal [["n1"], ["n3"]], [retrieval.nodes("1").map(&:id), retrieval.edges("1").map(&:to)]
  end

  def test_savepoints_read_for_one_intent
    %w[One Two].each { |title| store_graphs.work.write_intent(title:) }

    assert_equal ["2"], retrieval.savepoints("2").map(&:intent_id)
  end

  def test_linking_finds_links_to_the_intent_and_to_its_files
    link("2", "1")
    link("3", "1/plan.md")

    assert_equal %w[2 3], retrieval.linking("1").map(&:from_ref).sort
  end

  def test_linking_leaves_out_an_intent_whose_id_only_starts_the_same
    link("2", "10")
    link("3", "1a")

    assert_empty retrieval.linking("1")
  end

  def test_linking_leaves_out_another_origin
    link("2", "1", origin_id: "beef")

    assert_empty retrieval.linking("1")
  end
end
