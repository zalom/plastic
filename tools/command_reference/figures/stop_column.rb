# frozen_string_literal: true

module CommandReference
  module Figures
    # The stops of one event, stacked beside its box and wired to it.
    class StopColumn
      LEFT = 480
      WIDTH = 330

      def initialize(stops, event_box)
        @event_box = event_box
        @placed = StopBox.stack(stops, event_box.top)
      end

      def height = @placed.last&.then { |stop| stop.bottom - @event_box.top } || 0

      def draw(canvas) = @placed.each_with_index { |stop, at| stop.draw(canvas, route(stop, at)) }

      private

      def route(stop, at)
        middle = stop.middle
        Point.new(@event_box.right, leave(middle, at)).elbow_to(Point.new(LEFT, middle), across(at))
      end

      def across(at) = @event_box.right + 8 + (@placed.size - 1 - at) * 6

      def leave(middle, at) = (@placed.size == 1) ? [middle, @event_box.bottom - 10].min : @event_box.top + 12 + at * spread

      def spread = [(@event_box.height - 24) / (@placed.size - 1), 14].min
    end
  end
end
