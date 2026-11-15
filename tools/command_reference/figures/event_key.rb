# frozen_string_literal: true

module CommandReference
  module Figures
    # The key under a drawing: one swatch for each kind of box the drawing uses.
    class EventKey
      LANES = { code: "lane-code", agent: "lane-agent", command: "card", hook: "card" }.freeze
      STOPS = {
        failure: ["stop-failure", "Stops with a failure"], refusal: ["stop-refusal", "Stops for the owner"],
        handoff: ["stop-handoff", "Hands off, run again"], end: ["stop-end", "Ends"]
      }.freeze
      LETTER = 6.0
      GAP = 18

      def initialize(events)
        @events = events
      end

      def draw(canvas, top)
        items.reduce(EventRow::STEP_LEFT) { |left, (css, words)| left + swatch(canvas, Box.new(left, top, 14, 14), css, words) }
      end

      def height = 34

      private

      def swatch(canvas, box, css, words)
        canvas.rect(box, css, rx: 3)
        canvas.text(box.at(20, 12), words, "k")
        20 + (words.size * LETTER).ceil + GAP
      end

      def items = [*lane_items, *stop_items]

      def lane_items = LANES.keys.select { |lane| lanes.include?(lane) }.map { |lane| [LANES.fetch(lane), LANE_LABELS.fetch(lane)] }

      def stop_items = STOPS.keys.select { |kind| kinds.include?(kind) }.map { |kind| STOPS.fetch(kind) }

      def lanes = @events.map(&:lane)

      def kinds = @events.flat_map { |event| event.stops.map(&:kind) }
    end
  end
end
