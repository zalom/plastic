# frozen_string_literal: true

require_relative "knowledge/roadmap/state"
require_relative "knowledge/roadmap/form"
require_relative "roadmap_graph_print"

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
        row = @retrieval.roadmaps.find(@slug)
        lines = [Form::LINE, "# #{Form.escape(row.title)}", "", *Form.fields(row, %i[slug title goal opened_at]), "", *batches, *RoadmapGraphPrint.new(@retrieval, @slug).lines]
        "#{lines.join("\n")}\n"
      end

      private

      def batches = @retrieval.roadmaps.batches(@slug).flat_map { |batch| Form.batch_lines(batch, item_lines(batch.position)) }

      def item_lines(position)
        @retrieval.roadmaps.items(@slug).select { |item| item.batch == position }.flat_map { |item| [item_line(item), *Form.indented(item, %i[item position title goal done intent_id mark]), ""] }
      end

      def item_line(item) = "- [#{box(item)}] #{item.item} #{Form.escape(item.title)} — #{state_of(item)}"

      def state_of(item) = Knowledge::Roadmap::State.of(item, @retrieval)

      def box(item) = CHECKED.fetch(state_of(item), " ")
    end
  end
end
