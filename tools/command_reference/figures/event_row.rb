# frozen_string_literal: true

module CommandReference
  module Figures
    # One event of a call as a numbered box, with the stops of the call beside it.
    class EventRow
      STEP_LEFT = 24
      STEP_WIDTH = 400
      STOP_LEFT = 480
      STOP_WIDTH = 330
      LANE_CSS = { code: "lane-code", agent: "lane-agent", command: "card", hook: "card" }.freeze
      TAG_CSS = { code: "tag tag-code", agent: "tag tag-agent", command: "tag tag-muted", hook: "tag tag-muted" }.freeze

      attr_reader :top

      def self.lead(event) = event.way ? Words.wrap(event.way, 100).size * 16 + 4 : 0

      def initialize(event, top)
        @event = event
        @top = top
      end

      def bottom = top + [box.height, stops_height].max

      def box = Box.new(STEP_LEFT, top, STEP_WIDTH, 34 + words.size * 17)

      def draw(canvas, previous)
        wire_from(canvas, previous) if previous && @event.joined
        caption(canvas)
        canvas.rect(box, LANE_CSS.fetch(@event.lane))
        label(canvas)
        write(canvas)
        stop_boxes.each_with_index { |(stop, place, lines), at| draw_stop(canvas, stop, place, lines, at) }
      end

      private

      def words = @words ||= Words.wrap(@event.text, 52)

      def caption(canvas)
        return unless @event.way

        lines = Words.wrap(@event.way, 100)
        lines.each_with_index { |line, at| canvas.text(Point.new(STEP_LEFT, top - 8 - (lines.size - at) * 16 + 12), line, "way") }
      end

      def write(canvas) = words.each_with_index { |line, at| canvas.text(box.at(40, 42 + at * 17), line, "t") }

      def label(canvas)
        canvas.dot(box.at(20, 19), "badge")
        canvas.text(box.at(20, 23).middle, @event.number, "badge-t")
        canvas.text(box.at(40, 22), @event.label, TAG_CSS.fetch(@event.lane))
      end

      def wire_from(canvas, previous)
        start = previous.box.at(40, previous.box.height)
        canvas.wire([start, start.shift(0, top - start.top)])
      end

      def stops_height = stop_boxes.empty? ? 0 : stop_boxes.last[1].bottom - top

      def stop_boxes
        @stop_boxes ||= @event.stops.each_with_object([]) { |stop, all| all << place_stop(stop, all) }
      end

      def place_stop(stop, all)
        lines = stop.words.flat_map { |each| Words.wrap(each, 46) }
        at = all.empty? ? top : all.last[1].bottom + 8
        [stop, Box.new(STOP_LEFT, at, STOP_WIDTH, 30 + lines.size * 16), lines]
      end

      def draw_stop(canvas, stop, place, lines, at)
        canvas.wire(route(place, at), "wire-#{stop.kind}")
        canvas.rect(place, "stop-#{stop.kind}")
        canvas.text(place.at(12, 18), stop.tag, "tag tag-#{stop.kind}")
        lines.each_with_index { |line, row| canvas.text(place.at(12, 36 + row * 16), line, "t") }
      end

      def route(place, at)
        middle = place.top + place.height / 2
        elbow(Point.new(box.right, leave(middle, at)), Point.new(STOP_LEFT, middle), across(at))
      end

      def across(at) = box.right + 8 + (stop_boxes.size - 1 - at) * 6

      def leave(middle, at) = (stop_boxes.size == 1) ? [middle, box.bottom - 10].min : box.top + 12 + at * spread

      def spread = [(box.height - 24) / (stop_boxes.size - 1), 14].min

      def elbow(edge, goal, across) = (edge.top == goal.top) ? [edge, goal] : [edge, Point.new(across, edge.top), Point.new(across, goal.top), goal]
    end
  end
end
