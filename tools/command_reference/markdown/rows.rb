# frozen_string_literal: true

module CommandReference
  module Markdown
    # A table row for one step of a workflow.
    class StepRow
      def initialize(row, links)
        @row = row
        @links = links
      end

      def to_s = "| #{Words.cell(@row.name)} | #{@row.kind_words} | #{@row.check_cell} | #{@links.code(@row.file, @row.line)} |"
    end

    # A table row for one outcome of a workflow.
    class OutcomeRow
      def initialize(outcome, flow, owner)
        @outcome = outcome
        @flow = flow
        @owner = owner
      end

      def to_s
        "| `:#{@outcome.name}` | #{condition} | #{Words.cell(then_words)} | #{@owner.links.code(@outcome.file, @outcome.line)} |"
      end

      private

      def condition
        return (@outcome.name == :handoff) ? "when a step is left" : "when every done check holds" if @flow.agent?
        return "always" if @flow.outcomes.size == 1

        @outcome.fallback ? "otherwise" : "when `#{Words.cell(@outcome.check)}`"
      end

      def then_words = @outcome.ends? ? "#{@outcome.exit_words}; #{@outcome.next_words}" : runs

      def runs
        short = Words.short(@owner.page.flow(@outcome.to).klass)
        "runs [#{short}](##{short.downcase})"
      end
    end

    # A table row for one workflow of a command's chain.
    class FlowRow
      def initialize(flow, links)
        @flow = flow
        @links = links
      end

      def to_s
        short = @flow.short
        "| [#{short}](##{short.downcase}) | #{@flow.lane} | #{@links.code(@flow.file, @flow.line)} |"
      end
    end

    # A table row for one way a command call ends.
    class EndingRow
      def initialize(ending, links)
        @ending = ending
        @links = links
      end

      def to_s = "| #{Words.cell(@ending.text)} | #{@ending.exit_code} | #{Words.cell(@ending.next_text)} | #{@links.code(@ending.file, @ending.line)} |"
    end
  end
end
