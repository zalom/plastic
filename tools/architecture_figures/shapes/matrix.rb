# frozen_string_literal: true

module ArchitectureFigures
  module Shapes
    # A table of steps against graphs.
    class Matrix < Data.define(:left, :top, :columns, :heads, :rows)
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
