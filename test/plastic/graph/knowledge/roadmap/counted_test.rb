# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeRoadmapCountedTest < Plastic::TestCase
  Roadmap = Plastic::Graph::Knowledge::Roadmap

  def setup
    super
    @graphs = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1")
    @counted = Roadmap::Counted.new(@graphs.databases.fetch(:store))
  end

  def test_a_write_that_adds_a_row_is_a_change
    assert @counted.changed { |batch| batch.put(:roadmaps, { slug: "plan", title: "plan", goal: nil, opened_at: "T", updated_at: "T" }) }
  end

  def test_a_write_that_matches_no_row_is_no_change
    refute @counted.changed { |batch| batch.remove(:roadmap_edges, roadmap: "plan", from: "a", to: "b") }
  end
end
