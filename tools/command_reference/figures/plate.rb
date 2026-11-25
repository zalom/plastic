# frozen_string_literal: true

module CommandReference
  module Figures
    # A card of the workflows drawing: a tag, then the words of the card.
    class Plate
      LINE = 17
      WIDTH = 254
      TAGS = { code: "tag tag-code", agent: "tag tag-agent" }.freeze

      def initialize(canvas)
        @canvas = canvas
      end

      def self.lines(words, width = 32) = Words.wrap(words, width)

      def flow(card, flow)
        lane = flow.lane.to_sym
        card.paint(@canvas, "lane-#{lane}", TAGS.fetch(lane), LANE_LABELS.fetch(lane))
      end

      def stop(card, stop) = shape(card, *stop.look)

      def shape(card, kind, tag) = card.paint(@canvas, "stop-#{kind}", "tag tag-#{kind}", tag)

      def stack(left, top, across, ending)
        card = Card.at(left, top, across, ending.words.flat_map { |each| Plate.lines(each, across / 8) })
        stop(card, ending)
        card.height
      end
    end
  end
end
