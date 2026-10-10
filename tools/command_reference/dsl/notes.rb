# frozen_string_literal: true

module CommandReference
  module Dsl
    Note = Data.define(:row, :tag, :lines, :css, :tag_css)

    # Boxes beside a code panel, each level with the row it explains and stacked so none overlap.
    class Notes
      def initialize(canvas, bases)
        @canvas = canvas
        @bases = bases
      end

      def draw(x, width, notes)
        floor = 0
        notes.each_with_index do |note, at|
          top = [@bases.fetch(note.row) - 14, floor].max
          floor = top + box(note, x, top, width, at + 1) + 6
        end
      end

      private

      def box(note, x, top, width, number)
        height = (note.lines.size > 1) ? 26 + note.lines.size * 15 : 22
        @canvas.rect(x, top, width, height, note.css)
        badge(x + 14, top + 12, number) if note.lines.size > 1
        @canvas.text(x + ((note.lines.size > 1) ? 30 : 8), top + 15, note.tag, note.tag_css)
        lines(note, x, top)
        height
      end

      def lines(note, x, top)
        return @canvas.text(x + 18 + note.tag.size * 6.4, top + 15, note.lines.first, "tm") if note.lines.size == 1

        note.lines.each_with_index { |line, at| @canvas.text(x + 10, top + 31 + at * 15, line, at.zero? ? "tb" : "tm") }
      end

      def badge(x, y, words)
        @canvas.raw(%(<circle cx="#{x}" cy="#{y}" r="8" class="badge"/>), y + 8)
        @canvas.text(x, y + 4, words, "badge-t", anchor: "middle")
      end
    end
  end
end
