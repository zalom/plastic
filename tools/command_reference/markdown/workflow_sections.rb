# frozen_string_literal: true

module CommandReference
  module Markdown
    # One section per workflow of a command: its drawing, its steps and its outcomes.
    class WorkflowSections
      attr_reader :page, :links

      def initialize(page, links)
        @page = page
        @links = links
      end

      def lines = @page.flows.flat_map { |flow| FlowSection.new(flow, self).lines }
    end

    # The section of one workflow.
    class FlowSection
      def initialize(flow, owner)
        @flow = flow
        @owner = owner
      end

      def lines = [*heading, *Prose.lines(@flow.comment), *picture, *steps, *outcomes, *says, *facts]

      private

      def heading = ["### #{@flow.short}", "", "The #{@flow.lane} workflow `:#{@flow.key}`, in #{@owner.links.code(@flow.file, @flow.line)}.", ""]

      def picture = ["![How #{@flow.short} runs: its steps, where it stops, and its outcomes](#{@flow.key}.svg)", ""]

      def steps
        ["| Step | Kind | Check | Code |", "| --- | --- | --- | --- |", *@flow.rows.map { |row| StepRow.new(row, @owner.links).to_s }, ""]
      end

      def outcomes
        ["| Outcome | When | Then | Code |", "| --- | --- | --- | --- |", *@flow.outcomes.map { |outcome| OutcomeRow.new(outcome, @flow, @owner).to_s }, ""]
      end

      def says = @flow.rows.select(&:say).flat_map(&:saying)

      def facts
        names = @flow.facts.map { |fact| "`#{fact}`" }.join(", ")
        names.empty? ? [] : ["It sets #{names}.", ""]
      end
    end
  end
end
