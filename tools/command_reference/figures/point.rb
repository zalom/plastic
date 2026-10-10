# frozen_string_literal: true

module CommandReference
  module Figures
    # A place on a drawing, counted from its top left corner; words placed at it start there.
    Point = Data.define(:left, :top) do
      def shift(across, down) = Point.new(left + across, top + down)

      def side = "start"

      def box(width, height) = Box.new(left - width / 2, top, width, height)

      def ending = Anchored.new(self, "end")

      def middle = Anchored.new(self, "middle")

      def to_s = "#{left} #{top}"
    end
  end
end
