# frozen_string_literal: true

require_relative "knowledge/roadmap/state"
require_relative "knowledge/roadmap/form"

module Plastic
  module Graph
    # The markdown file of one roadmap, printed from its rows in form 2: a form line, then a
    # labeled line for each value, so a reader turns the file back into the same rows.
    class RoadmapPrint
      CHECKED = { "done" => "x", "dropped" => "x" }.freeze
      Form = Knowledge::Roadmap::Form

      def initialize(retrieval, slug)
        @retrieval = retrieval
        @slug = slug
      end

      def text
        row = @retrieval.roadmap(@slug)
        lines = [Form::LINE, "# #{Form.escape(row.title)}", "", *fields(row, %i[slug title goal opened_at]), "", *batches,
          "## Graph", "", *edge_lines, "", *edge_records, "## Log", "", *log_lines]
        "#{lines.join("\n")}\n"
      end

      private

      def fields(record, names) = names.map { |name| Form.labeled(name, record.public_send(name)) }

      def indented(record, names) = fields(record, names).map { |line| "  #{line}" }

      def batches = @retrieval.batches(@slug).flat_map { |batch| batch_lines(batch) }

      def batch_lines(batch)
        ["## Batch #{batch.position}: #{Form.escape(batch.title)}", "", *fields(batch, %i[title goal done]), "", *item_lines(batch.position)]
      end

      def item_lines(position)
        @retrieval.roadmap_items(@slug).select { |item| item.batch == position }.flat_map { |item| [item_line(item), *indented(item, %i[item position title goal done intent_id mark]), ""] }
      end

      def item_line(item) = "- [#{box(item)}] #{item.item} #{Form.escape(item.title)} — #{state_of(item)}"

      def state_of(item) = Knowledge::Roadmap::State.of(item, @retrieval)

      def box(item) = CHECKED.fetch(state_of(item), " ")

      def edge_lines = @retrieval.roadmap_items(@slug).map { |item| needs_line(item.item) }

      def needs_line(name) = "- #{name} needs #{needs_of(name).join(" ").sub(/\A\z/, "nothing")}"

      def needs_of(name) = edges.select { |edge| edge.to == name }.map(&:from)

      def edges = (@edges ||= @retrieval.roadmap_edges(@slug))

      def edge_records = edges.flat_map { |edge| ["- edge", *indented(edge, %i[from to kind]), ""] }

      def log_lines = @retrieval.roadmap_log(@slug).flat_map { |line| ["- log", *indented(line, %i[position at session_id text])] }
    end
  end
end
