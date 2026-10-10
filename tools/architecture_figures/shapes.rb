# frozen_string_literal: true

require "cgi/escape"
require_relative "canvas"

module ArchitectureFigures
  # The drawable parts of a figure. See docs/contributing/ARCHITECTURE.md.
  # Part of the figure builder; see docs/contributing/ARCHITECTURE.md.
  module Shapes
    def self.text(at, style, content)
      left, top, anchor = at
      tail = anchor ? %( text-anchor="#{anchor}") : ""
      %(<text class="#{style}" x="#{left}" y="#{top}"#{tail}>#{CGI.escapeHTML(content)}</text>)
    end

    # A shape with a rectangle that arrows can start and end on.
    module Anchored
      def right = left + width

      def bottom = top + height

      def anchor(side, fraction = 0.5)
        across = left + (fraction * width)
        down = top + (fraction * height)
        { left: [left, down], right: [right, down], top: [across, top], bottom: [across, bottom] }.fetch(side)
      end
    end

    # One line of text.
    Label = Data.define(:left, :top, :text, :style) do
      def markup(_id) = Shapes.text([left, top], style, text)
    end

    # A card with a name, an optional kind and lines of description.
    Box = Data.define(:left, :top, :width, :name, :kind, :lines, :tone, :mono) do
      include Anchored

      def height = (kind ? 58 : 42) + (15 * lines.size) + 6

      def markup(_id) = [frame, caption, *notes].join("\n")

      private

      def inset = left + 16

      def frame = %(<rect class="box" x="#{left}" y="#{top}" width="#{width}" height="#{height}" rx="8"/><rect x="#{left}" y="#{top}" width="6" height="#{height}" rx="3" fill="#{Palette.color(tone)}"/>)

      def caption = [Shapes.text([inset, top + 24], mono ? "m" : "t", name), (Shapes.text([inset, top + 41], "s", "[#{kind}]") if kind)].compact.join

      def notes = lines.each_with_index.map { |line, row| Shapes.text([inset, top + (kind ? 61 : 45) + (15 * row)], "s", line) }
    end

    # A database drawn as a cylinder.
    Cylinder = Data.define(:left, :top, :width, :name, :lines, :tone) do
      include Anchored

      def height = 52 + (15 * lines.size)

      def markup(_id) = [body, rim, caption, *notes].join("\n")

      private

      def radius = width / 2.0

      def middle = left + radius

      def cap = top + 9

      def base = bottom - 9

      def body = %(<path class="box" d="M #{left} #{cap} L #{left} #{base} A #{radius} 9 0 0 0 #{right} #{base} L #{right} #{cap} Z"/>)

      def rim = %(<ellipse class="box" cx="#{middle}" cy="#{cap}" rx="#{radius}" ry="9" style="stroke: #{Palette.color(tone)}"/>)

      def caption = Shapes.text([middle, top + 36, "middle"], "m", name)

      def notes = lines.each_with_index.map { |line, row| Shapes.text([middle, top + 54 + (15 * row), "middle"], "s", line) }
    end

    # A dashed frame around a group of cards.
    Zone = Data.define(:left, :top, :width, :height, :name) do
      include Anchored

      def markup(_id) = %(<rect class="zone" x="#{left}" y="#{top}" width="#{width}" height="#{height}" rx="12"/>) + Shapes.text([left + 14, top + 20], "s", name)
    end

    # A line with an arrowhead and a note on its longest stretch.
    Arrow = Data.define(:points, :note, :dashed) do
      def markup(id) = [path(id), *words].join("\n")

      private

      def path(id) = %(<path class="flow" d="#{points.each_with_index.map { |(px, py), at| "#{at.zero? ? "M" : "L"} #{px} #{py}" }.join(" ")}"#{' stroke-dasharray="4 3"' if dashed} marker-end="url(##{id}-arrow)"/>)

      def words = note.each_with_index.map { |line, row| Shapes.text(spot(row), "al", line) }

      def longest = points.each_cons(2).max_by { |(px, py), (qx, qy)| (qx - px).abs + (qy - py).abs }

      def level? = longest.map(&:last).uniq.one?

      def lift(row) = level? ? -7 - (13 * (note.size - 1 - row)) : 4 + (13 * row)

      def spot(row)
        (ax, ay), (bx, by) = longest
        [((ax + bx) / 2.0).round, (((ay + by) / 2.0) + lift(row)).round, "middle"]
      end
    end

    # A row of colored swatches with their meaning.
    Key = Data.define(:left, :top, :items) do
      def markup(_id) = items.each_with_index.map { |(tone, label), at| swatch(left + (at * 150), tone, label) }.join("\n")

      private

      def swatch(shift, tone, label) = %(<rect x="#{shift}" y="#{top - 10}" width="11" height="11" rx="2" fill="#{Palette.color(tone)}"/>) + Shapes.text([shift + 17, top], "s", label)
    end
  end
end
