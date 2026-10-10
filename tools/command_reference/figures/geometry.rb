# frozen_string_literal: true

require "cgi"
require "forwardable"

module CommandReference
  module Figures
    WINGS = {
      down: [[-5, -8], [0, 0], [5, -8]], left: [[8, -5], [0, 0], [8, 5]], right: [[-8, -5], [0, 0], [-8, 5]]
    }.freeze
    DIRECTIONS = { 0 => :down, 1 => :left, -1 => :right }.freeze

    # A place on a drawing, counted from its top left corner; words placed at it start there.
    Point = Data.define(:left, :top) do
      def shift(across, down) = Point.new(left + across, top + down)

      def side = "start"

      def box(width, height) = Box.new(left - width / 2, top, width, height)

      def ending = Anchored.new(self, "end")

      def middle = Anchored.new(self, "middle")

      def to_s = "#{left} #{top}"
    end

    # A place that words end at or center on.
    Anchored = Data.define(:point, :side) do
      extend Forwardable

      def_delegators :point, :left, :top
    end

    # A rectangle on a drawing.
    Box = Data.define(:left, :top, :width, :height) do
      def right = left + width

      def bottom = top + height

      def center = left + width / 2

      def at(across, down) = Point.new(left + across, top + down)

      def beside(gap, limit) = Box.new(right + gap, top, limit - right - gap, height)

      def head = Point.new(center, top)

      def route_to(target, drop)
        turn = bottom + drop
        [foot, Point.new(center, turn), Point.new(target.center, turn), target.head]
      end

      def foot = Point.new(center, bottom)

      def attributes = %(x="#{left}" y="#{top}" width="#{width}" height="#{height}")
    end

    # One run of words at a place, anchored at its start, middle or end.
    Label = Data.define(:place, :words, :css) do
      def markup = %(<text x="#{place.left}" y="#{place.top}" class="#{css}" text-anchor="#{place.side}">#{CGI.escapeHTML(words.to_s)}</text>)
    end

    # A small filled dot, such as the number on a note.
    Circle = Data.define(:center, :css) do
      def bottom = center.top + 8

      def markup = %(<circle cx="#{center.left}" cy="#{center.top}" r="8" class="#{css}"/>)
    end

    # The arrow tip at the end of a wire, pointing the way the last leg runs.
    Head = Data.define(:tip, :from) do
      def markup = %(<path d="M #{corners.join(" L ")} Z" class="head"/>)

      private

      def corners = WINGS.fetch(DIRECTIONS.fetch(from.left <=> tip.left)).map { |across, down| tip.shift(across, down) }
    end

    # A line through points, ending in an arrow.
    Path = Data.define(:points, :css) do
      def bottom = points.map(&:top).max

      def markup = %(<path d="M #{points.join(" L ")}" class="#{css}"/>\n#{Head.new(points.last, points[-2]).markup})
    end

    # The SVG around the shapes of a drawing.
    Frame = Data.define(:width, :height, :title, :parts) do
      def markup(style)
        [opening, "<title>#{CGI.escapeHTML(title)}</title>", style, %(<rect width="100%" height="100%" class="ground"/>), *parts, "</svg>"].join("\n")
      end

      private

      def opening = %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{width} #{height}" width="#{width}" height="#{height}" role="img" xml:space="preserve">)
    end
  end
end
