# frozen_string_literal: true

module Plastic
  class TestCase
    # Roadmap r1 with batch 1 and its items, for the roadmap workflow tests.
    module RoadmapHelper
      def roadmap(done: "d") = store_graphs.work.write_batch("r1", 1, fields: roadmap_fields("T", goal: "G", done:))

      def item(id, needs: [], batch: 1) = store_graphs.work.add_item("r1", id, batch, fields: roadmap_fields(id.upcase), needs:)

      def roadmap_fields(title, goal: nil, done: nil) = Plastic::Graph::Knowledge::Roadmap::Writer::Fields.new(title:, goal:, done:)
    end
  end
end
