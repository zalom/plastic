# frozen_string_literal: true

require_relative "shapes"

module ArchitectureFigures
  module Shapes
    # A glyph for writes, reads or prints, followed by a few words.
    Mark = Data.define(:left, :top, :verb, :text) do
      def markup(_id) = [glyph, Shapes.text([left + 18, top], "s", text)].join("\n")

      private

      def glyph
        ink = Palette.color(:ink)
        case verb
        when :writes then dot(%(r="4" fill="#{ink}"))
        when :reads then dot(%(r="3.5" fill="none" stroke="#{ink}" stroke-width="1.4"))
        else %(<rect x="#{left + 1}" y="#{top - 8}" width="8" height="8" fill="none" stroke="#{ink}" stroke-width="1.4"/>)
        end
      end

      def dot(attributes) = %(<circle cx="#{left + 5}" cy="#{top - 4}" #{attributes}/>)
    end

    # One row of a Matrix: a step with its commands, and what it does to each graph.
    MatrixRow = Data.define(:left, :top, :columns, :row) do
      def height = (([row.fetch(:commands).size + 1, *row.fetch(:cells).map(&:size)].max * 16) + 18)

      def markup(_id) = [rule, *step, *cells].join("\n")

      private

      def rule = %(<line x1="#{left}" y1="#{top}" x2="#{left + columns.last + 270}" y2="#{top}" stroke="#{Palette.color(:rule)}" stroke-width="1"#{' stroke-dasharray="5 4"' if row[:dashed]}/>)

      def step = [Shapes.text([left, top + 20], "t", row.fetch(:title)), *row.fetch(:commands).each_with_index.map { |command, at| Shapes.text([left, top + 38 + (16 * at)], "m", command) }]

      def cells = row.fetch(:cells).each_with_index.flat_map { |cell, at| entries(cell, left + columns[at]) }

      def entries(cell, column) = cell.each_with_index.map { |(verb, text), line| Mark.new(left: column, top: top + 20 + (16 * line), verb: verb, text: text).markup(nil) }
    end

    # A table of steps against graphs.
    Matrix = Data.define(:left, :top, :columns, :heads, :rows) do
      def markup(_id) = [*heads_markup, *placed.map { |row| row.markup(nil) }].join("\n")

      private

      def heads_markup = heads.zip([0, *columns]).map { |head, shift| Shapes.text([left + shift, top + 18], "t", head) }

      def placed
        cursor = top + 34
        rows.map { |row| MatrixRow.new(left: left, top: cursor, columns: columns, row: row).tap { |placed_row| cursor += placed_row.height } }
      end
    end
  end
end
