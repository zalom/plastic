# frozen_string_literal: true

require_relative "../intent"
require_relative "../roadmap"

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        # An item's state, derived from its mark, its intent and its predecessors.
        # Never stored: the rows hold only what the state is computed from.
        class State
          DONE_STATUSES = %w[done abandoned].freeze
          IN_FLIGHT_STATUSES = Intent::GROUPS.fetch("active")

          def self.of(item, retrieval) = new(item, retrieval).name

          def initialize(item, retrieval)
            @item = item
            @retrieval = retrieval
            intent_id = item.intent_id
            @intent = intent_id && retrieval.intent(intent_id)
          end

          def name
            return "done" if done?
            return "dropped" if @item.dropped?
            return "in flight" if in_flight?
            return "blocked" if blocked?
            "ready"
          end

          def done?
            return DONE_STATUSES.include?(@intent.status) if @intent
            %w[delivered abandoned].include?(@item.mark)
          end

          def resolved? = done? || @item.dropped?

          private

          def in_flight? = @intent ? IN_FLIGHT_STATUSES.include?(@intent.status) : false

          def blocked? = predecessors.any? { |row| !State.new(row, @retrieval).resolved? }

          def predecessors
            roadmap = @item.roadmap
            from_items = @retrieval.roadmap_edges(roadmap).select { |edge| edge.to == @item.item }.map(&:from)
            @retrieval.roadmap_items(roadmap).select { |row| from_items.include?(row.item) }
          end
        end
      end
    end
  end
end
