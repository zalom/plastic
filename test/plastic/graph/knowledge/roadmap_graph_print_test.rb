# frozen_string_literal: true

require_relative "../../../test_helper"

class GraphRoadmapGraphPrintTest < Plastic::TestCase
  Edge = Struct.new(:from, :to, :kind)
  Item = Struct.new(:item)
  Line = Struct.new(:position, :at, :session_id, :text)

  class Roadmaps
    def items(_slug) = [Item.new("a"), Item.new("b")]

    def edges(_slug) = [Edge.new("a", "b", "needs")]

    def log(_slug) = [Line.new(1, "2026-01-01T10:00:00Z", "s1", "said")]
  end

  Retrieval = Struct.new(:roadmaps)

  def lines = Plastic::Graph::RoadmapGraphPrint.new(Retrieval.new(Roadmaps.new), "plan").lines

  def test_each_item_lists_what_it_needs
    assert_equal ["- a needs nothing", "- b needs a"], lines[2, 2]
  end

  def test_each_edge_is_a_record
    assert_includes lines, "- edge"
    assert_includes lines, "  kind: needs"
  end

  def test_each_log_line_is_a_record
    assert_equal ["## Log", ""], lines.each_cons(2).find { |pair| pair.first == "## Log" }
    assert_includes lines, "  text: said"
  end
end
