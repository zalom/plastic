# frozen_string_literal: true

module Plastic
  module Workflows
    # The print lines of a roadmap: one batch with its done criteria, and one
    # item with its state and the items it waits for.
    module RoadmapLines
      def self.batch(batch)
        heading = ["batch #{batch.position}: #{batch.title}", batch.goal].compact.reject(&:empty?).join(" - ")
        [heading, *batch.done_lines.map { |line| "  done: #{line}" }]
      end

      def self.item(item, state, edges)
        name = item.item
        "item #{name}: #{item.title} - #{state}, waits for #{waits(edges, name)}"
      end

      def self.waits(edges, name)
        from = edges.select { |edge| edge.to == name }.map(&:from)
        from.empty? ? "nothing" : from.join(" ")
      end
    end
  end
end
