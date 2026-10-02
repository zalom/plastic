# frozen_string_literal: true

require_relative "../../test_helper"

class GraphViewTest < Plastic::TestCase
  fixtures :alpha_synced

  def test_sync_up_never_reads_graph_json
    write("store/1--alpha/graph.json", '{"nodes":[{"id":"forged","state":"done"}]}')
    before = retrieval.nodes("1").map(&:to_h)
    sync = Plastic::Graph::Sync.new(folder:, retrieval:, databases: store_graphs.databases)

    sync.apply(sync.plan(:up))

    assert_equal before, retrieval.nodes("1").map(&:to_h)
  end

  def test_the_reader_refuses_direct_graph_import
    read = Plastic::Graph::Reader.new(folder, { "1" => retrieval.intent("1") }, origin).read("store/1--alpha/graph.json")

    assert_raises(Plastic::Invalid) { apply_read(read) }
  end
end
