# frozen_string_literal: true

module ArchitectureFigures
  module Shapes
    # A card with a name, an optional kind and lines of description.
    class Box < Data.define(:left, :top, :width, :name, :kind, :lines, :tone, :mono)
      include Anchored

      def height = 48 + shift + (15 * lines.size)

      def markup(_id) = [frame, caption, *notes].join("\n")

      private

      def shift = kind ? 16 : 0

      def inset = left + 16

      def frame = %(<rect class="box" x="#{left}" y="#{top}" width="#{width}" height="#{height}" rx="8"/><rect x="#{left}" y="#{top}" width="6" height="#{height}" rx="3" fill="#{Palette.color(tone)}"/>)

      def caption = [Shapes.text([inset, top + 24], mono ? "m" : "t", name), (Shapes.text([inset, top + 41], "s", "[#{kind}]") if kind)].compact.join

      def notes = lines.each_with_index.map { |line, row| Shapes.text([inset, top + 45 + shift + (15 * row)], "s", line) }
    end
  end
end
