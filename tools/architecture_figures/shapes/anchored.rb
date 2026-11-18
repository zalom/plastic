# frozen_string_literal: true

module ArchitectureFigures
  module Shapes
    # A shape with a rectangle that arrows can start and end on.
    module Anchored
      def right = left + width

      def bottom = top + height

      def bounds = [left, top, right, bottom]

      def anchor(side, fraction = 0.5)
        across = left + (fraction * width)
        down = top + (fraction * height)
        { left: [left, down], right: [right, down], top: [across, top], bottom: [across, bottom] }.fetch(side)
      end
    end
  end
end
