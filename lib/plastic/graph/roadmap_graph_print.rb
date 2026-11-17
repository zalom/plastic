# frozen_string_literal: true

require_relative "knowledge/roadmap/form"

module Plastic
  module Graph
    # The graph and log sections of a roadmap file in form 2: what each item needs, each edge as a record, and each log line.
    class RoadmapGraphPrint
      Form = Knowledge::Roadmap::Form

      def initialize(retrieval, slug)
        @retrieval = retrieval
        @slug = slug
      end

      def lines = ["## Graph", "", *edge_lines, "", *edge_records, "## Log", "", *log_lines]

      private

      def edge_lines = @retrieval.roadmaps.items(@slug).map { |item| needs_line(item.item) }

      def needs_line(name) = "- #{name} needs #{needs_of(name).join(" ").sub(/\A\z/, "nothing")}"

      def needs_of(name) = edges.select { |edge| edge.to == name }.map(&:from)

      def edges = (@edges ||= @retrieval.roadmaps.edges(@slug))

      def edge_records = edges.flat_map { |edge| ["- edge", *Form.indented(edge, %i[from to kind]), ""] }

      def log_lines = @retrieval.roadmaps.log(@slug).flat_map { |line| ["- log", *Form.indented(line, %i[position at session_id text])] }
    end
  end
end
