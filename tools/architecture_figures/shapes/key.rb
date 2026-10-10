# frozen_string_literal: true

module ArchitectureFigures
  module Shapes
    # A row of colored swatches with their meaning.
    class Key < Data.define(:left, :top, :items)
      def markup(_id) = items.each_with_index.map { |(tone, label), at| swatch(left + (at * 150), tone, label) }.join("\n")

      private

      def swatch(shift, tone, label) = %(<rect x="#{shift}" y="#{top - 10}" width="11" height="11" rx="2" fill="#{Palette.color(tone)}"/>) + Shapes.text([shift + 17, top], "s", label)
    end
  end
end
