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

      Beside = Data.define(:gates, :ends) do
        def any? = gates.any? || ends.any?

        def gate_kind = (kinds.size > 1) ? :both : kinds.first

        def kinds = gates.map(&:kind).uniq
      end

      def initialize(canvas, plate, box, beside)
        @canvas = canvas
        @plate = plate
        @box = box
        @beside = beside
      end

      def draw = [@box.bottom, ends, gates].max

      private

      def ends
        stops = @beside.ends
        return @box.bottom if stops.empty?

        middles = []
        bottom = stops.reduce(@box.top) { |at, stop| at + stacked(at, stop, middles) + 8 }
        bracket(middles)
        bottom
      end

      def stacked(top, stop, middles)
        height = @plate.stack(@box.left - GAP - WIDTH, top, WIDTH, stop)
        middles << top + height / 2
        height
      end

      def bracket(middles)
        left = @box.left
        spine = left - GAP / 2
        start = @box.at(0, @box.height / 2)
        level = start.top
        rule(start, Point.new(spine, level))
        spans(spine, [level, *middles])
        middles.each { |middle| arrow(spine, left - GAP, middle) }
      end

      def spans(spine, reaches)
        low, high = reaches.minmax
        rule(Point.new(spine, low), Point.new(spine, high))
      end

      def arrow(from, to, at) = @canvas.wire([Point.new(from, at), Point.new(to, at)], "wire-end")

      def rule(from, to) = @canvas.line([from, to], "wire-end")

      def gates = @beside.gate_kind&.then { |kind| gate_card(kind) } || @box.bottom

      def gate_card(kind)
        lines = Plate.lines(WORDS.fetch(kind), WIDTH / 8)
        shown, tag = LOOK.fetch(kind)
        card = Card.at(@box.right + GAP, @box.top, WIDTH, lines)
        @plate.shape(card, shown, tag)
        reach(@box.at(@box.width, @box.height / 2), GAP, "wire-#{shown}")
        card.bottom
      end

      def reach(from, across, css) = @canvas.wire([from, from.shift(across, 0)], css)
    end
  end
end
