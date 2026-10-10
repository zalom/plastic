# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/check_roadmap"

class CheckRoadmapTest < Plastic::TestCase
  Fields = Plastic::Graph::Knowledge::Roadmap::Writer::Fields

  def setup
    super
    work = store_graphs.work
    work.write_batch("r1", 1, fields: Fields.new(title: "T", goal: "G", done: "d"))
    work.add_item("r1", "a", 1, fields: Fields.new(title: "A", goal: nil, done: nil), needs: [])
  end

  def check(slug = "r1") = run_workflow(Plastic::Workflows::CheckRoadmap, slug:)

  def test_a_clean_roadmap_has_no_findings
    outcome, context = check

    assert_equal [:done, ["no findings"]], [outcome, context.printed]
  end

  def test_an_edge_to_an_item_off_the_roadmap_is_a_finding_that_fails_the_call
    store_graphs.databases[:work].transaction { |batch| batch.put(:roadmap_edges, { roadmap: "r1", from: "a", to: "ghost", kind: "after" }) }

    outcome, context = check

    assert_equal ["finding: edge a to ghost names an item not on roadmap r1"], context.printed
    assert_equal "code_check_roadmap, gate: see the findings above", outcome.message
  end

  def test_an_unknown_roadmap_fails_the_call
    assert_equal "code_check_roadmap, gate: no roadmap r9", check("r9").first.message
  end
end
