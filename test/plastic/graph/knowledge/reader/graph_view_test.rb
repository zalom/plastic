# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeReaderGraphViewTest < Plastic::TestCase
  fixtures :alpha_synced

  def test_sync_up_never_reads_graph_json
    write("store/1--alpha/graph.json", '{"nodes":[{"id":"forged","state":"done"}]}')
    before = retrieval.nodes("1").map(&:to_h)
    sync = Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases)

    sync.apply(sync.plan(:up))

    assert_equal before, retrieval.nodes("1").map(&:to_h)
  end

  def test_the_reader_refuses_direct_graph_import
    read = Plastic::Graph::Knowledge::Reader.new(folder, { "1" => retrieval.intent("1") }, origin).read("store/1--alpha/graph.json")

    assert_raises(Plastic::Invalid) { apply_read(read) }
  end
end

class KnowledgeReaderGraphViewRestoreTest < Plastic::TestCase
  fixtures :alpha_synced

  def printed_node_ids = JSON.parse(folder.read("store/1--alpha/graph.json")).fetch("nodes").map { |row| row.fetch("id") }

  def test_sync_down_regenerates_from_rows_after_a_tampered_view
    node = store_graphs.work.add_node(intent_id: "1", title: "Trusted", criterion: "Done")
    write("store/1--alpha/graph.json", "not even JSON")
    sync = Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases)

    sync.apply(sync.plan(:down, overwrite: nil))

    assert_equal [node.id], printed_node_ids
  end
end
