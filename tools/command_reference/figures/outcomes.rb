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
        @drawing.text(Workflow::SPINE, top + 8, "ENDS ON", "tag tag-muted")
        @flow.outcomes.reduce(top + 16) { |y, outcome| one(outcome, y) + 8 }
      end

      private

      def one(outcome, top)
        goes = goes_words(outcome).flat_map { |line| Words.wrap(line, 50) }
        height = [conditions(outcome).size + 1, goes.size].max * 14 + 14
        left(outcome, top, height)
        right(outcome, top, height, goes)
        top + height
      end

      def left(outcome, top, height)
        @drawing.rect(Workflow::SPINE, top, LEFT, height, "card")
        @drawing.text(Workflow::SPINE + 10, top + 16, ":#{outcome.name}", "tm")
        conditions(outcome).each_with_index { |line, at| @drawing.text(Workflow::SPINE + 10, top + 32 + at * 14, line, "tm tag-muted") }
      end

      def right(outcome, top, height, goes)
        x = Workflow::SPINE + LEFT + 36
        @drawing.wire([[Workflow::SPINE + LEFT, top + 16], [x, top + 16]])
        @drawing.rect(x, top, Workflow::WIDTH - x - 16, height, (outcome.to == :noop) ? "end" : "lane-#{@page.flow(outcome.to).lane}")
        goes.each_with_index { |line, at| @drawing.text(x + 10, top + 17 + at * 14, line, "t") }
      end

      def conditions(outcome) = Words.wrap(condition(outcome), 36)

      def condition(outcome)
        return "when a step is left" if @flow.lane == "agent" && outcome.name == :handoff
        return "when every done check holds" if @flow.lane == "agent"
        return "always" if @flow.outcomes.size == 1
        return "otherwise" if outcome.fallback

        "when #{outcome.check}"
      end

      def goes_words(outcome)
        return ["next workflow: #{Words.short(@page.flow(outcome.to).klass)}"] unless outcome.to == :noop

        [(outcome.name == :handoff) ? "hands off: prints the steps left, exit #{outcome.exit_code}" : "the call finishes, exit 0",
          next_words(outcome), "because: #{outcome.because}"]
      end

      def next_words(outcome) = outcome.offers ? "next: #{outcome.offers}" : "prints no next: line"
    end
  end
end
