# frozen_string_literal: true

module Plastic
  module Graph
    # An item's state, derived from its mark, its intent and its predecessors.
    # Never stored: the rows hold only what the state is computed from.
    module RoadmapState
      DONE_STATUSES = %w[done abandoned].freeze
      IN_FLIGHT_STATUSES = %w[open active parked].freeze

      module_function

      def of(item, retrieval)
        return "done" if done?(item, retrieval)
        return "dropped" if item.dropped?
        return "in flight" if in_flight?(item, retrieval)
        return "blocked" if blocked?(item, retrieval)
        "ready"
      end

      def done?(item, retrieval)
        intent = intent_of(item, retrieval)
        return DONE_STATUSES.include?(intent.status) if intent
        %w[delivered abandoned].include?(item.mark)
      end

      def in_flight?(item, retrieval)
        intent = intent_of(item, retrieval)
        !intent.nil? && IN_FLIGHT_STATUSES.include?(intent.status)
      end

      def blocked?(item, retrieval)
        predecessors(item, retrieval).any? { |row| !resolved?(row, retrieval) }
      end

      def resolved?(item, retrieval)
        state = of(item, retrieval)
        state == "done" || state == "dropped"
      end

      def predecessors(item, retrieval)
        from_items = retrieval.roadmap_edges(item.roadmap).select { |edge| edge.to == item.item }.map(&:from)
        retrieval.roadmap_items(item.roadmap).select { |row| from_items.include?(row.item) }
      end

      def intent_of(item, retrieval) = item.intent_id && retrieval.intent(item.intent_id)
    end
  end
end
