# frozen_string_literal: true

module ArchitectureFigures
  module Shapes
    # One row of a Matrix: a step with its commands, and what it does to each graph.
    class MatrixRow < Data.define(:left, :top, :columns, :row)
      def height = (([row.fetch(:commands).size + 1, *row.fetch(:cells).map(&:size)].max * 16) + 18)

      def markup(_id) = [rule, *step, *cells].join("\n")

      private

      def rule = %(<line x1="#{left}" y1="#{top}" x2="#{left + columns.last + 270}" y2="#{top}" stroke="#{Palette.color(:rule)}" stroke-width="1"#{' stroke-dasharray="5 4"' if row[:dashed]}/>)

      def step = [Shapes.text([left, top + 20], "t", row.fetch(:title)), *row.fetch(:commands).each_with_index.map { |command, at| Shapes.text([left, top + 38 + (16 * at)], "m", command) }]

      def cells = row.fetch(:cells).each_with_index.flat_map { |cell, at| entries(cell, left + columns[at]) }

      def entries(cell, column) = cell.each_with_index.map { |(verb, text), line| Mark.new(left: column, top: top + 20 + (16 * line), verb: verb, text: text).markup(nil) }
    end
  end
end
