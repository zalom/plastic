# frozen_string_literal: true

module CommandReference
  module Figures
    # A box of a drawing with the lines of words that fill it.
    Card = Data.define(:box, :lines) do
      def self.at(left, top, width, lines) = new(Box.new(left, top, width, 32 + lines.size * Plate::LINE), lines)

      def height = box.height

      def bottom = box.bottom

      def paint(canvas, css, tag_css, tag)
        canvas.rect(box, css)
        canvas.text(box.at(12, 20), tag, tag_css)
        canvas.stack(box.at(12, 40), lines, "t", Plate::LINE)
      end
    end
  end
end
