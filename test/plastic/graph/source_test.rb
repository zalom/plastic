# frozen_string_literal: true

require_relative "../../test_helper"

class SourceTest < Plastic::TestCase
  def nodes = Plastic::Graph::SOURCES.fetch(:nodes)

  def origin = Plastic::Graph::Origin.new(@plastic_home).id

  def setup
    super
    work = store_graphs.work
    work.write_intent(title: "Alpha")
    work.write_intent(title: "Beta")
    work.add_node(intent_id: "2", title: "Second")
    work.add_node(intent_id: "1", title: "First")
  end

  def test_a_read_with_an_intent_id_reads_only_that_intent
    assert_equal ["First"], nodes.read(store_graphs.databases, origin:, intent_id: "1").map(&:title)
  end

  def test_a_read_with_no_intent_id_reads_every_intent_in_order
    assert_equal %w[First Second], nodes.read(store_graphs.databases, origin:, intent_id: nil).map(&:title)
  end

  def test_a_read_leaves_out_the_rows_another_installation_wrote
    assert_empty nodes.read(store_graphs.databases, origin: "elsewhere", intent_id: nil)
  end

  def test_each_source_builds_its_own_record
    assert_kind_of Plastic::Graph::Work::Node, nodes.read(store_graphs.databases, origin:, intent_id: "1").first
  end
end
