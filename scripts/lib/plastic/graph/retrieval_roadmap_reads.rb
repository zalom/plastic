# frozen_string_literal: true

module Plastic
  module Graph
    # Exposes the ordered roadmap read family through a retrieval graph.
    module RetrievalRoadmapReads
      def roadmap(slug) = roadmaps.roadmap(slug)
      def batches(slug) = roadmaps.batches(slug)
      def roadmap_items(slug) = roadmaps.items(slug)
      def roadmap_edges(slug) = roadmaps.edges(slug)
      def roadmap_log(slug) = roadmaps.log(slug)
    end
  end
end
