# frozen_string_literal: true

require_relative "shapes"

module ArchitectureFigures
  # Part of the figure builder; see docs/contributing/ARCHITECTURE.md.
  module Shapes
    # A box of terminal output lines.
    Terminal = Data.define(:left, :top, :width, :lines) do
      def height = (16 * lines.size) + 20

      def markup(_id) = [frame, *rows].join("\n")

      private

      def frame = %(<rect class="box" x="#{left}" y="#{top}" width="#{width}" height="#{height}" rx="8" stroke="#{Palette.color(:rule)}"/>)

      def rows = lines.each_with_index.map { |line, at| Shapes.text([left + 16, top + 24 + (16 * at)], "r", line) }
    end
  end
end
