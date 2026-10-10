# frozen_string_literal: true

module CommandReference
  module Figures
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
  end
end
