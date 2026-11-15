# frozen_string_literal: true

module CommandReference
  module Figures
    # The cards beside the first workflow of a call: where the call ends early on the left, where a check stops it on the right.
    class Sides
      WIDTH = 222
      GAP = 44
      WORDS = {
        failure: "A check fails. The events below show each check.",
        refusal: "The step belongs to the owner. The events below show each check.",
        both: "A check fails or the step belongs to the owner. The events below show each check."
      }.freeze
      LOOK = { failure: [:failure, "STOPS, EXIT 1"], refusal: [:refusal, "STOPS, EXIT 3"], both: [:refusal, "STOPS, EXIT 1 OR 3"] }.freeze

      def initialize(canvas, plate)
        @canvas = canvas
        @plate = plate
      end

      def self.needed?(stops, early) = stops.gates.any? || (early && stops.closing.any?)

      def draw(box, stops, early)
        [box.bottom, (early ? ends(box, stops.closing) : box.bottom), gates(box, stops.gates)].max
      end

      private

      def ends(box, stops)
        return box.bottom if stops.empty?

        middles = []
        bottom = stops.reduce(box.top) { |at, stop| at + stacked(box, at, stop, middles) + 8 }
        bracket(box, middles)
        bottom
      end

      def stacked(box, top, stop, middles)
        height = @plate.stack(box.left - GAP - WIDTH, top, WIDTH, stop)
        middles << top + height / 2
        height
      end

      def bracket(box, middles)
        spine = box.left - GAP / 2
        start = box.at(0, box.height / 2)
        rule(start, Point.new(spine, start.top))
        spans(spine, [start.top, *middles])
        middles.each { |middle| arrow(spine, box.left - GAP, middle) }
      end

      def spans(spine, reaches) = rule(Point.new(spine, reaches.min), Point.new(spine, reaches.max))

      def arrow(from, to, at) = @canvas.wire([Point.new(from, at), Point.new(to, at)], "wire-end")

      def rule(from, to) = @canvas.raw(%(<path d="M #{from} L #{to}" class="wire-end"/>), to.top)

      def gates(box, stops)
        return box.bottom if stops.empty?

        kinds = stops.map(&:kind).uniq
        gate_card(box, (kinds.size > 1) ? :both : kinds.first)
      end

      def gate_card(box, kind)
        lines = Plate.lines(WORDS.fetch(kind), WIDTH / 8)
        shown, tag = LOOK.fetch(kind)
        card = Box.new(box.right + GAP, box.top, WIDTH, Plate.height(lines))
        @plate.card(card, "stop-#{shown}", "tag tag-#{shown}", tag, lines)
        reach(box.at(box.width, box.height / 2), GAP, "wire-#{shown}")
        card.bottom
      end

      def reach(from, across, css) = @canvas.wire([from, from.shift(across, 0)], css)
    end
  end
end
