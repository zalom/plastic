# frozen_string_literal: true

module CommandReference
  module Dsl
    # One note: the code row it explains, a tag, its lines and the colors of its box and tag.
    Note = Data.define(:row, :tag, :lines, :css, :tag_css) do
      def long? = lines.size > 1

      def height = long? ? 26 + lines.size * 15 : 22

      def tag_left = long? ? 30 : 8
    end

    # Boxes beside a code panel, each level with the row it explains and stacked so none overlap.
    class Notes
      def initialize(canvas, bases)
        @canvas = canvas
        @bases = bases
      end

      def draw(column, notes)
        notes.each_with_index.reduce(0) do |floor, (note, at)|
          frame = column.with(top: [@bases.fetch(note.row) - 14, floor].max, height: note.height)
          NoteBox.new(@canvas, note, frame).draw(at + 1)
          frame.bottom + 6
        end
      end
    end

    # Paints one note in its frame.
    class NoteBox
      def initialize(canvas, note, frame)
        @canvas = canvas
        @note = note
        @frame = frame
      end

      def draw(number)
        @canvas.rect(@frame, @note.css)
        badge(number) if long?
        @canvas.text(@frame.at(@note.tag_left, 15), @note.tag, @note.tag_css)
        long? ? stacked : beside
      end

      private

      def long? = @note.long?

      def beside = @canvas.text(@frame.at(18, 15).shift(@note.tag.size * 6.4, 0), @note.lines.first, "tm")

      def stacked
        first, *rest = @note.lines
        @canvas.text(@frame.at(10, 31), first, "tb")
        @canvas.roomy(@frame.at(10, 46), rest, "tm")
      end

      def badge(number)
        center = @frame.at(14, 12)
        @canvas.dot(center, "badge")
        @canvas.text(center.shift(0, 4).middle, number, "badge-t")
      end
    end
  end
end
