# frozen_string_literal: true

module CommandReference
  module Figures
    # One drawing: shapes go in as they are drawn, and to_s wraps them in an SVG.
    class Canvas
      attr_reader :height, :width

      def initialize(width, title)
        @width = width
        @title = title
        @height = 0
        @parts = []
      end

      def grow(bottom) = (@height = [@height, bottom].max)

      def rect(box, css, rx: 6)
        grow(box.bottom)
        @parts << %(<rect #{box.attributes} rx="#{rx}" class="#{css}"/>)
      end

      def raw(markup, bottom)
        grow(bottom)
        @parts << markup
      end

      def text(place, words, css) = (@parts << Label.new(place, words, css).markup)

      def paragraph(origin, lines, css) = lines.each_with_index { |line, at| text(origin.shift(0, at * 14), line, css) }

      def roomy(origin, lines, css) = lines.each_with_index { |line, at| text(origin.shift(0, at * 15), line, css) }

      def dot(center, css) = shape(Circle.new(center, css))

      def wire(points, css = "wire") = shape(Path.new(points, css))

      def to_s = document("")

      def standalone = document("<style>#{Style::STANDALONE}</style>")

      private

      def shape(found)
        grow(found.bottom)
        @parts << found.markup
      end

      def document(style) = Frame.new(@width, @height + 14, @title, @parts).markup(style)
    end
  end
end
