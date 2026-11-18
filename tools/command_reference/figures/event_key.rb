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
      GAP = 18

      Swatch = Data.define(:css, :words) do
        def draw(canvas, left, top)
          canvas.rect(Box.new(left, top, 14, 14), css, rx: 3)
          canvas.text(Point.new(left + 20, top + 12), words, "k")
          20 + Glyphs.width(words).ceil + GAP
        end
      end

      def initialize(events)
        @events = events
      end

      def draw(canvas, top)
        items.reduce(EventRow::STEP_LEFT) { |left, swatch| left + swatch.draw(canvas, left, top) }
      end

      def height = 34

      private

      def items = [*lane_items, *stop_items]

      def lane_items = LANES.keys.select { |lane| lanes.include?(lane) }.map { |lane| Swatch.new(LANES.fetch(lane), LANE_LABELS.fetch(lane)) }

      def stop_items = STOPS.keys.select { |kind| kinds.include?(kind) }.map { |kind| Swatch.new(*STOPS.fetch(kind)) }

      def lanes = @events.map(&:lane)

      def kinds = @events.flat_map { |event| event.stops.map(&:kind) }
    end
  end
end
