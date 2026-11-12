# frozen_string_literal: true

module Plastic
  module Workflows
    # The print lines of a roadmap: one batch with its done criteria, and one
    # item with its state and the items it needs.
    module RoadmapLines
      def self.batch(batch)
        heading = ["batch #{batch.position}: #{batch.title}", batch.goal].compact.reject(&:empty?).join(" - ")
        [heading, *batch.done_lines.map { |line| "  done: #{line}" }]
      end

      def self.item(item, state, edges)
        name = item.item
        "item #{name}: #{item.title} - #{state}, needs #{needs(edges, name)}"
      end

      def self.needs(edges, name)
        from = edges.select { |edge| edge.to == name }.map(&:from)
        from.empty? ? "nothing" : from.join(" ")
      end
    end
  end
end
