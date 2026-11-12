# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "roadmap_print"

module Plastic
  module Workflows
    # Prints each batch with its goal and done criteria, then each item with
    # its derived state, from the rows.
    class ShowRoadmap < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      gate "no roadmap %{slug}", stops: :failure, pass: ->(context) { !context.retrieval.roadmap(context.slug).nil? }

      read "print each batch and item" do |context|
        RoadmapPrint.call(context)
      end

      outcome :done, offers: "plastic roadmap next %{slug}", because: "the rows hold this roadmap"
    end
  end
end
