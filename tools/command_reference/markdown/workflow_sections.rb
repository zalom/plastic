# frozen_string_literal: true

module CommandReference
  module Markdown
    # One section per workflow of a command: its drawing, its steps and its outcomes.
    class WorkflowSections
      KINDS = { read: "read", gate: "gate", step: "step", agent: "agent step" }.freeze

      def initialize(page, links, blocks)
        @page = page
        @links = links
        @blocks = blocks
      end

      def lines = @page.flows.flat_map { |flow| section(flow) }

      private

      def section(flow)
        name = Words.short(flow.klass)
        ["### #{name}", "", "The #{flow.lane} workflow `:#{flow.key}`, in #{@links.code(flow.file, flow.line)}.", "", *text(flow.comment),
          "![How #{name} runs: its steps, where it stops, and its outcomes](#{flow.key}.svg)", "",
          "| Step | Kind | Check | Code |", "| --- | --- | --- | --- |", *flow.rows.map { |row| step_row(row) }, "",
          "| Outcome | When | Then | Code |", "| --- | --- | --- | --- |", *flow.outcomes.map { |outcome| outcome_row(flow, outcome) }, "",
          *says(flow), *facts(flow)]
      end

      def text(comment) = @blocks.blocks(comment).flat_map { |kind, body| (kind == :code) ? ["```ruby", body, "```", ""] : [body, ""] }

      def step_row(row)
        "| #{cell(row.name)} | #{KINDS.fetch(row.kind)}#{stops(row)} | #{"`#{cell(row.check)}`" if row.check} | #{@links.code(row.file, row.line)} |"
      end

      def stops(row)
        return "" unless row.kind == :gate

        (row.stops == :refusal) ? ", stops with exit 3" : ", stops with exit 1"
      end

      def outcome_row(flow, outcome)
        "| `:#{outcome.name}` | #{condition(flow, outcome)} | #{cell(then_words(outcome))} | #{@links.code(outcome.file, outcome.line)} |"
      end

      def condition(flow, outcome)
        return "when a step is left" if flow.lane == "agent" && outcome.name == :handoff
        return "when every done check holds" if flow.lane == "agent"
        return "always" if flow.outcomes.size == 1

        outcome.fallback ? "otherwise" : "when `#{cell(outcome.check)}`"
      end

      def then_words(outcome)
        return "runs [#{Words.short(@page.flow(outcome.to).klass)}](##{Words.short(@page.flow(outcome.to).klass).downcase})" unless outcome.to == :noop

        "#{(outcome.name == :handoff) ? "hands off, exit #{outcome.exit_code}" : "finishes, exit 0"}; #{outcome.offers ? "next: #{outcome.offers}" : "prints no next: line"}"
      end

      def says(flow) = flow.rows.select(&:say).flat_map { |row| ["The agent step \"#{row.name}\" prints:", "", "> #{row.say.gsub("\n", "\n> ")}", ""] }

      def facts(flow) = flow.facts.empty? ? [] : ["It sets #{flow.facts.map { |fact| "`#{fact}`" }.join(", ")}.", ""]

      def cell(text) = text.to_s.gsub("|", "\\|")
    end
  end
end
