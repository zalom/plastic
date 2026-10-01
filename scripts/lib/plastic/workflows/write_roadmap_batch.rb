# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/roadmap_writer"

module Plastic
  module Workflows
    # Writes a roadmap batch's goal and done criteria, and the roadmap row
    # the first time it is named.
    class WriteRoadmapBatch < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :batch

      step "write the batch", done: ->(context) { !context.batch.nil? } do |context|
        fields = Graph::RoadmapWriter::Fields.new(title: context.title, goal: context.goal, done: context.done)
        context[:batch] = context.work.write_batch(context.slug, context.position.to_i, fields:)
      end

      read "say what was written" do |context|
        context.print("batch: #{context.slug} #{context.batch.position} #{context.batch.title}")
      end

      outcome :done, offers: "plastic roadmap show %{slug}", because: "batch %{position} of %{slug} is written"
    end
  end
end
