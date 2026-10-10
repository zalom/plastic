# frozen_string_literal: true

module CommandReference
  module Dsl
    # Code on the left of a drawing and a note beside each part of it that explains it.
    class CodeDrawing
      WIDTH = 940

      def initialize(rows)
        @rows = Layout.new(chars).rows(rows)
      end

      def canvas = Figures::Canvas.new(WIDTH, title).tap { |drawing| paint(drawing) }

      private

      attr_reader :rows

      def paint(drawing)
        panel = CodePanel.new(drawing, rows, chars)
        bases = panel.draw(Figures::Point.new(16, 16))
        Notes.new(drawing, bases).draw(column(panel.width), notes)
      end

      def column(panel_width) = Figures::Box.new(16 + panel_width + gap, 0, WIDTH - panel_width - side, 0)
    end
  end
end
