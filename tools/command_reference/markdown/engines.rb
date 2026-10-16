# frozen_string_literal: true

module CommandReference
  module Markdown
    # The rows of a command's workflows in the words of workflow engines: trigger, activities, transitions and outcomes.
    class Engines
      def initialize(page)
        @page = page
        @flows = page.flows
      end

      def lines
        ["In the words of workflow engines, the rows are these four parts:", "", "- **Trigger**: #{trigger}", "- **Activities**: #{activities}",
          "- **Transitions**: #{transitions}", "- **Outcomes**: #{outcomes}", ""]
      end

      private

      def trigger
        first = "the call starts the workflow `#{@page.flow(@page.entry).path}`"
        (@flows.size == 1) ? "#{first}." : "#{first}; each later workflow starts from an outcome of the one before it."
      end

      def activities
        kinds = { read: ["read", "reads"], step: ["step", "steps"], agent: ["agent step", "agent steps"] }
        counts = kinds.filter_map { |kind, (one, many)| count(rows(kind).size, one, many) }
        counts.empty? ? "none." : "#{sentence(counts)}."
      end

      def sentence(parts) = (parts.size > 1) ? "#{parts[0..-2].join(", ")} and #{parts.last}" : parts.first

      def count(size, one, many) = ("#{size} #{(size == 1) ? one : many}" if size.positive?)

      def rows(kind) = @flows.flat_map(&:rows).select { |row| row.kind == kind }

      def transitions = [gates, steps, *edges].compact.join("; ").then { |text| "#{text}." }

      def gates
        size = rows(:gate).size
        "#{size} #{(size == 1) ? "gate stops" : "gates stop"} the call when #{(size == 1) ? "its check fails" : "their checks fail"}" if size.positive?
      end

      def steps = ("a step runs only while its done check fails" if (rows(:step) + rows(:agent)).any?)

      def edges = @page.edges.map { |edge| "#{@page.flow(edge.from).short} goes to #{@page.flow(edge.to).short} on #{edge.words.gsub(/(:\w+)/, '`\1`')}" }

      def outcomes
        ending = @flows.flat_map { |flow| flow.outcomes.select(&:ends?).map { |outcome| ending(flow, outcome) } }
        "#{ending.join(", ")} #{(ending.size == 1) ? "ends" : "end"} the call."
      end

      def ending(flow, outcome) = (@flows.size == 1) ? "`:#{outcome.name}`" : "`:#{outcome.name}` of #{flow.short}"
    end
  end
end
