# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeLegacyRoadmapMigrationTest < Plastic::TestCase
  Legacy = Plastic::Graph::Knowledge::Legacy

  def migrate
    write("roadmaps/plan.md", "# Plan\n\n## Batches\n\n### Batch 1 — First\n- [ ] 7 Build it — queued\n")
    counts = Hash.new(0)
    Legacy::RoadmapMigration.new(store_graphs, folder.path("."), counts).call(Legacy::Roadmaps.new(folder.path(".")).parse)
    counts
  end

  def test_migrating_counts_the_roadmaps_and_items
    assert_equal [1, 1], migrate.values_at(:roadmaps, :roadmap_items)
  end

  def test_migrating_writes_the_items_of_the_roadmap
    migrate

    assert_equal ["Build it"], retrieval.roadmaps.items("plan").map(&:title)
  end
end
