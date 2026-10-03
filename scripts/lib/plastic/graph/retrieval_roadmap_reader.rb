# frozen_string_literal: true

require_relative "roadmap"

module Plastic
  module Graph
    # Reads ordered roadmap records for one origin.
    class RetrievalRoadmapReader
      QUERIES = {
        roadmap: ["SELECT * FROM roadmaps WHERE origin_id = :origin AND slug = :slug", Roadmap],
        batches: ["SELECT * FROM batches WHERE origin_id = :origin AND roadmap = :slug ORDER BY position", RoadmapBatch],
        items: ["SELECT * FROM roadmap_items WHERE origin_id = :origin AND roadmap = :slug ORDER BY batch, position", RoadmapItem],
        edges: ['SELECT * FROM roadmap_edges WHERE origin_id = :origin AND roadmap = :slug ORDER BY CAST("from" AS INTEGER), "from"', RoadmapEdge],
        log: ["SELECT * FROM roadmap_log WHERE origin_id = :origin AND roadmap = :slug ORDER BY position", RoadmapLogLine]
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
        sql, type = query(name)
        row = @database.row(sql, origin: @origin_id, slug:)
        row && type.from_h(row)
      end

      def many(name, slug)
        sql, type = query(name)
        @database.rows(sql, origin: @origin_id, slug:).map { |row| type.from_h(row) }
      end

      def query(name) = QUERIES.fetch(name)
    end
  end
end
