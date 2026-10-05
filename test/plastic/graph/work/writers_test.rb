# frozen_string_literal: true

require_relative "../../../test_helper"

class WorkWritersTest < Plastic::TestCase
  def writers
    graphs = store_graphs
    Plastic::Graph::Work::Writers.new(graphs.databases, graphs.retrieval, folder, "s-1")
  end

  def test_each_writer_is_built_once_and_kept
    built = writers

    assert_same built.nodes, built.nodes
  end

  def test_each_writer_writes_to_the_store_it_was_built_on
    built = writers
    built.intents.write(title: "Alpha")
    built.nodes.add_node(intent_id: "1", title: "Build")

    assert_equal ["Build"], retrieval.nodes("1").map(&:title)
  end

  def test_the_session_writer_writes_under_the_store_name
    writers.sessions.take_lock("1", session_id: "s-1", mode: "auto")

    assert_equal "global", retrieval.lock("1").store
  end
end
