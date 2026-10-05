# frozen_string_literal: true

require_relative "../knowledge/roadmap"

module Plastic
  module Graph
    module Retrieval
      # Reads ordered roadmap records for one origin.
      class RoadmapReader
        QUERIES = {
          roadmap: ["SELECT * FROM roadmaps WHERE origin_id = :origin AND slug = :slug", Knowledge::Roadmap],
          batches: ["SELECT * FROM batches WHERE origin_id = :origin AND roadmap = :slug ORDER BY position", Knowledge::Roadmap::Batch],
          items: ["SELECT * FROM roadmap_items WHERE origin_id = :origin AND roadmap = :slug ORDER BY batch, position", Knowledge::Roadmap::Item],
          edges: ['SELECT * FROM roadmap_edges WHERE origin_id = :origin AND roadmap = :slug ORDER BY CAST("from" AS INTEGER), "from"', Knowledge::Roadmap::Edge],
          log: ["SELECT * FROM roadmap_log WHERE origin_id = :origin AND roadmap = :slug ORDER BY position", Knowledge::Roadmap::LogLine]
        }.freeze

        def initialize(database, origin_id)
          @database = database
          @origin_id = origin_id
        end

        def roadmap(slug) = one(:roadmap, slug)
        def batches(slug) = many(:batches, slug)
        def items(slug) = many(:items, slug)
        def edges(slug) = many(:edges, slug)
        def log(slug) = many(:log, slug)

        private

        def one(name, slug)
          sql, type = QUERIES.fetch(name)
          row = @database.row(sql, origin: @origin_id, slug:)
          row && type.from_h(row)
        end

        def many(name, slug)
          sql, type = QUERIES.fetch(name)
          @database.rows(sql, origin: @origin_id, slug:).map { |row| type.from_h(row) }
        end
      end
    end
  end
end
