# frozen_string_literal: true

module CommandReference
  module Figures
    # One stop of a call as a box beside its event, with the words of the stop wrapped to fit.
    StopBox = Data.define(:stop, :box, :lines) do
      def self.stack(stops, top)
        stops.reduce([]) { |placed, stop| placed + [fit(stop, placed.last&.below || top)] }
      end

      def self.fit(stop, top)
        lines = stop.words.flat_map { |each| Words.wrap(each, 46) }
        new(stop, Box.new(StopColumn::LEFT, top, StopColumn::WIDTH, 30 + lines.size * 16), lines)
      end

      def below = bottom + 8

      def bottom = box.bottom

      def middle = box.top + box.height / 2

      def draw(canvas, route)
        canvas.wire(route, "wire-#{stop.kind}")
        frame(canvas)
        tag(canvas)
        write(canvas)
      end

      private

      def frame(canvas) = canvas.rect(box, "stop-#{stop.kind}")

      def tag(canvas) = canvas.text(box.at(12, 18), stop.tag, "tag tag-#{stop.kind}")

      def write(canvas) = lines.each_with_index { |line, row| canvas.text(box.at(12, 36 + row * 16), line, "t") }
    end
  end
end
