# frozen_string_literal: true

module CommandReference
  module Markdown
    # One row of a workflow told as a sentence: what it does and when it stops the call.
    class RowItem
      def initialize(row)
        @row = row
      end

      def to_s = send(@row.kind)

      private

      def read = "Read: #{name}."

      def gate = "Gate: passes when #{check}; otherwise the call stops with exit #{(@row.stops == :refusal) ? 3 : 1} and prints #{name}."

      def step = "Step: #{name}. #{done("so a second call skips it")}"

      def agent = "Agent step: #{name}. #{done("while it fails, the call prints its `say:` text")}"

      def done(then_words) = always? ? "Runs on every call; its done check is #{check}.#{agent_note}" : "Done when #{check}, #{then_words}."

      def agent_note = (@row.kind == :agent) ? " The call prints its `say:` text." : String.new

      def always? = Array(@row.check).join == "false"

      def check = Words.span(Array(@row.check).join(" "))

      def name = Words.plain(@row.name).strip.delete_suffix(".")
    end

    # One outcome of a workflow told as a sentence: when it holds and what it does.
    class OutcomeItem
      def initialize(outcome, flow, page)
        @outcome = outcome
        @flow = flow
        @page = page
      end

      def to_s = "Outcome `:#{@outcome.name}`, #{condition}: #{@outcome.ends? ? ending : start}."

      private

      def condition
        return (@outcome.name == :handoff) ? "when a step is left" : "when every done check holds" if @flow.agent?
        return "always" if @flow.outcomes.size == 1

        @outcome.fallback ? "otherwise" : "when #{Words.span(@outcome.check)}"
      end

      def ending = "#{(@outcome.name == :handoff) ? "hands off with" : "finishes with"} exit #{@outcome.exit_code}; #{offer}"

      def offer = (found = Array(@outcome.offers).first) ? "next: #{Words.plain(found)}" : Endings::NONE

      def start
        target = @page.flow(@outcome.to)
        "starts the workflow [#{target.path}](##{target.anchor})"
      end
    end
  end
end
