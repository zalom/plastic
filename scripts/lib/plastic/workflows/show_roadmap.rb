# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "roadmap_print"

module Plastic
  module Workflows
    # Prints each batch with its goal and done criteria, then each item with
    # its derived state, and reprints roadmaps/SLUG.md from rows.
    class ShowRoadmap < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :printed_paths

      gate "no roadmap %{slug}", stops: :failure, pass: ->(context) { !context.retrieval.roadmap(context.slug).nil? }

      read "print each batch and item" do |context|
        RoadmapPrint.call(context)
      end

      step "reprint the roadmap file", done: ->(context) { !context.printed_paths.nil? } do |context|
        context[:printed_paths] = context.work.print_roadmap(context.slug)
      end

      outcome :done, offers: "plastic roadmap next %{slug}", because: "the roadmap file matches the rows"
    end
  end
end
