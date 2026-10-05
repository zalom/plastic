# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/lines"

class LinesTest < Minitest::Test
  Node = Struct.new(:id, :state, :title)
  Ruling = Struct.new(:id, :text, :supersedes)

  def lines = Plastic::Workflows::Lines

  def test_a_node_line_names_its_state_and_title
    assert_equal "node: n1 open Build", lines.node(Node.new(id: "n1", state: "open", title: "Build"))
  end

  def test_a_ready_node_line_leaves_out_the_state
    assert_equal "ready: n1 Build", lines.ready_node(Node.new(id: "n1", state: "open", title: "Build"))
  end

  def test_a_superseded_ruling_is_marked
    rulings = [Ruling.new(id: "r1", text: "old"), Ruling.new(id: "r2", text: "new", supersedes: "r1")]

    assert_equal ["ruling: r1 old (superseded)", "ruling: r2 new"], lines.rulings(rulings)
  end
end
