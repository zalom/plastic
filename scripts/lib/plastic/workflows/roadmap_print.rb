# frozen_string_literal: true

require_relative "roadmap_lines"
require_relative "../graph/knowledge/roadmap/state"

module Plastic
  module Workflows
    # Prints each batch of a roadmap, or the one batch at the asked position,
    # and under each batch its items with their derived state.
    class RoadmapPrint
      def self.call(context) = new(context).call

      def initialize(context)
        @context = context
        @retrieval = context.retrieval
        @slug = context.slug
      end

      def call = batches.each { |batch| print_batch(batch) }

      private

      def batches
        all = @retrieval.batches(@slug)
        position = @context.position
        position ? all.select { |row| row.position == position.to_i } : all
      end

      def print_batch(batch)
        RoadmapLines.batch(batch).each { |line| @context.print(line) }
        items(batch.position).each { |item| @context.print(item_line(item)) }
      end

      def items(position) = @retrieval.roadmap_items(@slug).select { |item| item.batch == position }

      def item_line(item)
        state = Graph::Knowledge::Roadmap::State.of(item, @retrieval)
        RoadmapLines.item(item, state, @retrieval.roadmap_edges(@slug))
      end
    end
  end
end
