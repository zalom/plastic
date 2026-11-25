# frozen_string_literal: true

module CommandReference
  module Figures
    # One event of a call as a numbered box, with the stops of the call beside it.
    class EventRow
      STEP_LEFT = 24
      STEP_WIDTH = 400
      TAG_CSS = { code: "tag tag-code", agent: "tag tag-agent", command: "tag tag-muted", hook: "tag tag-muted" }.freeze

      attr_reader :top

      def self.lead(event) = event.way&.then { |way| Words.wrap(way, 100).size * 16 + 4 } || 0

      def self.after(rows, event)
        below = rows.last&.then { |row| row.bottom + 26 } || 64
        new(event, below + lead(event))
      end

      def initialize(event, top)
        @event = event
        @top = top
      end

      def bottom = top + [box.height, stops.height].max

      def box = Box.new(STEP_LEFT, top, STEP_WIDTH, 34 + words.size * 17)

      def joint = box.at(40, box.height)

      def draw(canvas, previous)
        canvas.wire(previous.joint.down_to(top)) if previous && @event.joined
        caption(canvas)
        canvas.rect(box, EventKey::LANES.fetch(@event.lane))
        label(canvas)
        write(canvas)
        stops.draw(canvas)
      end

      private

      def words = @words ||= Words.wrap(@event.text, 52)

      def stops = @stops ||= StopColumn.new(@event.stops, box)

      def caption(canvas) = way.each_with_index { |line, at| canvas.text(Point.new(STEP_LEFT, top - 8 - (way.size - at) * 16 + 12), line, "way") }

      def way = @way ||= Array(@event.way).flat_map { |each| Words.wrap(each, 100) }

      def write(canvas) = words.each_with_index { |line, at| canvas.text(box.at(40, 42 + at * 17), line, "t") }

      def label(canvas)
        canvas.dot(box.at(20, 19), "badge")
        canvas.text(box.at(20, 23).middle, @event.number, "badge-t")
        canvas.text(box.at(40, 22), @event.label, TAG_CSS.fetch(@event.lane))
      end
    end
  end
end
