# frozen_string_literal: true

require "cgi"

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

      def rect(x, y, width, height, css, rx: 6)
        grow(y + height)
        @parts << %(<rect x="#{x}" y="#{y}" width="#{width}" height="#{height}" rx="#{rx}" class="#{css}"/>)
      end

      def raw(markup, bottom)
        grow(bottom)
        @parts << markup
      end

      def text(x, y, words, css, anchor: "start")
        @parts << %(<text x="#{x}" y="#{y}" class="#{css}" text-anchor="#{anchor}">#{CGI.escapeHTML(words.to_s)}</text>)
      end

      def wire(points, css = "wire", head: true)
        grow(points.map(&:last).max)
        @parts << %(<path d="M #{points.map { |x, y| "#{x} #{y}" }.join(" L ")}" class="#{css}"/>)
        arrow(*points.last, points[-2]) if head
      end

      def to_s(standalone)
        height = @height + 14
        style = standalone ? "<style>#{Style::STANDALONE}</style>" : ""
        [svg_open(height), "<title>#{CGI.escapeHTML(@title)}</title>", style, %(<rect width="100%" height="100%" class="ground"/>), *@parts, "</svg>"].join("\n")
      end

      private

      def svg_open(height)
        %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{@width} #{height}" width="#{@width}" height="#{height}" role="img" xml:space="preserve">)
      end

      def arrow(x, y, from)
        @parts << %(<path d="M #{head_points(x, y, from)} Z" class="head"/>)
      end

      def head_points(x, y, from)
        return "#{x - 5} #{y - 8} L #{x} #{y} L #{x + 5} #{y - 8}" if from.first == x
        return "#{x + 8} #{y - 5} L #{x} #{y} L #{x + 8} #{y + 5}" if from.first > x

        "#{x - 8} #{y - 5} L #{x} #{y} L #{x - 8} #{y + 5}"
      end
    end
  end
end
