# frozen_string_literal: true

module ArchitectureFigures
  class Diagram
    # The path of one arrow: straight when its ends line up, otherwise bent.
    class Route < Data.define(:start, :finish, :out, :into)
      def points = aligned? ? [start, finish] : [start, *corners, finish]

      private

      def aligned? = start.first == finish.first || start.last == finish.last

      def flat = [out, into].map { |side| %i[left right].include?(side) }

      def corners
        (sx, sy), (fx, fy) = start, finish
        mx = (sx + fx) / 2
        my = (sy + fy) / 2
        { [true, false] => [[fx, sy]], [false, true] => [[sx, fy]],
          [true, true] => [[mx, sy], [mx, fy]], [false, false] => [[sx, my], [fx, my]] }.fetch(flat)
      end
    end
  end
end
