# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/knowledge/roadmap/writer"

module Plastic
  module Workflows
    # Adds one item to a roadmap batch, guarded against a missing batch, a
    # predecessor not on the roadmap, and a loop over roadmap_edges.
    class AddRoadmapItem < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :kind, :item

      forget_stop :problem, :kind, :item

      step "add the item", done: ->(context) { !context.item.nil? || !context.problem.nil? } do |context|
        fields = Graph::Knowledge::Roadmap::Writer::Fields.new(title: context.title, goal: context.goal, done: context.done)
        item, problem, kind = context.work.add_item(context.slug, context.item_id, context.position.to_i,
          fields:, after: context.needs)
        context[:item] = item
        context[:problem] = problem
        context[:kind] = kind
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.kind != :failure }
      gate "%{problem}", stops: :refusal, pass: ->(context) { context.kind != :refusal }

      read "say what was added" do |context|
        context.print("item: #{context.item.item} #{context.item.title}")
      end

      outcome :done, offers: "plastic roadmap show %{slug}", because: "item %{item_id} is on roadmap %{slug}"
    end
  end
end
