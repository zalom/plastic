# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Removes one needs edge; fails when no such edge exists.
    class RemoveRoadmapEdge < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :removed

      forget_stop :problem, :removed

      step "remove the edge", done: ->(context) { !context.removed.nil? } do |context|
        removed = context.work.remove_roadmap_edge(context.slug, context.from, context.to)
        context[:removed] = removed
        context[:problem] = removed ? nil : "no edge #{context.from} to #{context.to} on roadmap #{context.slug}"
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

      read "say what was removed" do |context|
        context.print("edge: #{context.from} to #{context.to} removed")
      end

      outcome :done, offers: "plastic roadmap show %{slug}", because: "edge %{from} to %{to} is gone"
    end
  end
end
