# frozen_string_literal: true

require_relative "knowledge/roadmap/state"

module Plastic
  module Graph
    # The markdown file of one roadmap, printed from its rows.
    class RoadmapPrint
      CHECKED = { "done" => "x", "dropped" => "x" }.freeze

      def initialize(retrieval, slug)
        @retrieval = retrieval
        @slug = slug
      end

      def text
        row = @retrieval.roadmap(@slug)
        lines = ["# #{row.title}", "", *goal_lines(row.goal), *batches,
          "## Graph", "", *edge_lines, "", "## Log", "", *log_lines]
        "#{lines.join("\n")}\n"
      end

      private

      def goal_lines(goal) = goal ? ["## Goal", "", goal, ""] : []

      def batches = @retrieval.batches(@slug).flat_map { |batch| batch_lines(batch) }

      def batch_lines(batch)
        batch => { position:, title: }
        ["## Batch #{position}: #{title}", "", *batch.done_lines.map { |line| "- #{line}" }, "", *item_lines(position), ""]
      end

      def item_lines(position)
        @retrieval.roadmap_items(@slug).select { |item| item.batch == position }.map { |item| item_line(item) }
      end

      def item_line(item) = "- [#{box(item)}] #{item.item} #{item.title} — #{state_of(item)}"

      def state_of(item) = Knowledge::Roadmap::State.of(item, @retrieval)

      def box(item) = CHECKED.fetch(state_of(item), " ")

      def edge_lines = @retrieval.roadmap_items(@slug).map { |item| needs_line(item.item) }

      def needs_line(name) = "- #{name} needs #{needs_of(name).join(" ").sub(/\A\z/, "nothing")}"

      def needs_of(name) = edges.select { |edge| edge.to == name }.map(&:from)

      def edges = (@edges ||= @retrieval.roadmap_edges(@slug))

      def log_lines = @retrieval.roadmap_log(@slug).map { |line| "- #{line.at} #{line.text}" }
    end
  end
end
