# frozen_string_literal: true

module CommandReference
  module Figures
    # What one outcome of a workflow says: when it holds and where it goes.
    class OutcomeWords
      def initialize(outcome, flow, target)
        @outcome = outcome
        @flow = flow
        @target = target
      end

      def name = @outcome.name

      def conditions = Words.wrap(condition, 36)

      def goes = lines.flat_map { |line| Words.wrap(line, 50) }

      def height = [conditions.size + 1, goes.size].max * 14 + 14

      def css = @outcome.ends? ? "end" : "lane-#{@target.lane}"

      private

      def condition
        return agent_condition if @flow.agent?
        return "always" if @flow.outcomes.size == 1
        return "otherwise" if @outcome.fallback

        "when #{@outcome.check}"
      end

      def agent_condition = (name == :handoff) ? "when a step is left" : "when every done check holds"

      def lines
        return ["next workflow: #{@target.short}"] unless @outcome.ends?

        [ending, next_line, "because: #{@outcome.because}"]
      end

      def ending = (name == :handoff) ? "hands off: prints the steps left, exit #{@outcome.exit_code}" : "the call finishes, exit 0"

      def next_line
        offers = @outcome.offers
        offers ? "next: #{offers}" : "prints no next: line"
      end
    end
  end
end
