# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeSyncReadabilityTest < Plastic::TestCase
  Readability = Plastic::Graph::Knowledge::Sync::Readability

  def setup
    super
    @intent = open_intent
    @path = "#{@intent.dir}/graph.json"
  end

  def write_nodes(nodes)
    graph = JSON.parse(File.read(store_path(@path)))
    write(@path, "#{JSON.pretty_generate(graph.merge("nodes" => nodes))}\n")
  end

  def unreadable = Readability.new(folder, retrieval, store_graphs.databases).call([@path])

  def node_rows = store_graphs.databases.fetch(:work).rows("SELECT id FROM nodes")

  def test_a_graph_whose_rows_the_database_refuses_is_unreadable_with_the_database_reason
    write_nodes([{ "id" => nil, "state" => "open", "title" => "T" }])

    assert_equal({ @path => "work_graph.db: NOT NULL constraint failed: nodes.id" }, unreadable)
  end

  def test_a_graph_the_database_accepts_is_readable_and_leaves_no_row
    write_nodes([{ "id" => "n1", "state" => "open", "title" => "T" }])

    assert_equal [{}, []], [unreadable, node_rows]
  end
end
