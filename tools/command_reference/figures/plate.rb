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

      def self.height(lines) = 32 + lines.size * LINE

      def flow(box, flow, lines)
        lane = flow.lane.to_sym
        card(box, "lane-#{lane}", TAGS.fetch(lane), LANE_LABELS.fetch(lane), lines)
      end

      def stop(box, stop, lines)
        card(box, "stop-#{stop.kind}", "tag tag-#{stop.kind}", stop.tag, lines)
      end

      def stack(left, top, across, ending)
        lines = ending.words.flat_map { |each| Plate.lines(each, across / 8) }
        stop(Box.new(left, top, across, Plate.height(lines)), ending, lines)
        Plate.height(lines)
      end

      def card(box, css, tag_css, tag, lines)
        @canvas.rect(box, css)
        @canvas.text(box.at(12, 20), tag, tag_css)
        lines.each_with_index { |line, at| @canvas.text(box.at(12, 40 + at * LINE), line, "t") }
      end
    end
  end
end
