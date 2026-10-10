# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/knowledge/roadmap/writer"

module Plastic
  module Workflows
    # Writes a roadmap batch's goal and done criteria on a roadmap that exists.
    class WriteRoadmapBatch < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      gate "no roadmap %{slug}", stops: :failure, offers: "plastic roadmap new %{slug}",
        because: "a batch belongs to a roadmap that roadmap new created",
        pass: ->(context) { !context.retrieval.roadmap(context.slug).nil? }

      sets :batch

      step "write the batch", done: ->(context) { !context.batch.nil? } do |context|
        fields = Graph::Knowledge::Roadmap::Writer::Fields.new(title: context.title, goal: context.goal, done: context.done)
        context[:batch] = context.work.write_batch(context.slug, context.position.to_i, fields:)
      end

      read "say what was written" do |context|
        context.print("batch: #{context.slug} #{context.batch.position} #{context.batch.title}")
      end

      outcome :done, offers: "plastic roadmap show %{slug}", because: "batch %{position} of %{slug} is written"
    end
  end
end
