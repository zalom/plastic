# frozen_string_literal: true

module CommandReference
  module Figures
    # The outcomes a workflow can end on, each with where it goes next.
    class Outcomes
      LEFT = 300

      def initialize(drawing, page, flow)
        @drawing = drawing
        @page = page
        @flow = flow
      end

      def draw(top)
        @drawing.text(Point.new(Workflow::SPINE, top + 8), "ENDS ON", "tag tag-muted")
        @flow.outcomes.reduce(top + 16) { |level, outcome| one(outcome, level) + 8 }
      end

      private

      def one(outcome, top)
        words = OutcomeWords.new(outcome, @flow, @page.flow(outcome.to))
        frame = Box.new(Workflow::SPINE, top, LEFT, words.height)
        card(frame, words)
        goes(frame, words)
        frame.bottom
      end

      def card(frame, words)
        @drawing.rect(frame, "card")
        @drawing.text(frame.at(10, 16), ":#{words.name}", "tm")
        @drawing.paragraph(frame.at(10, 32), words.conditions, "tm tag-muted")
      end

      def goes(frame, words)
        panel = frame.beside(36, Workflow::WIDTH - 16)
        @drawing.wire([frame.at(LEFT, 16), panel.at(0, 16)])
        @drawing.rect(panel, words.css)
        @drawing.paragraph(panel.at(10, 17), words.goes, "t")
      end
    end
  end
end
