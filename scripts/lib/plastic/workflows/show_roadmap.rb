# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/roadmap_state"

module Plastic
  module Workflows
    # Prints each batch with its goal and done criteria, then each item with
    # its derived state, and reprints roadmaps/SLUG.md from rows.
    class ShowRoadmap < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :printed_paths

      def self.batches_of(context)
        all = context.retrieval.batches(context.slug)
        context.position ? all.select { |row| row.position == context.position.to_i } : all
      end

      def self.print_batch(context, batch)
        context.print(["batch #{batch.position}: #{batch.title}", batch.goal].compact.reject(&:empty?).join(" - "))
        batch.done_lines.each { |line| context.print("  done: #{line}") }
        context.retrieval.roadmap_items(context.slug).select { |item| item.batch == batch.position }
          .each { |item| print_item(context, item) }
      end

      def self.print_item(context, item)
        state = Graph::RoadmapState.of(item, context.retrieval)
        from = context.retrieval.roadmap_edges(context.slug).select { |edge| edge.to == item.item }.map(&:from)
        waits = from.empty? ? "nothing" : from.join(" ")
        context.print("item #{item.item}: #{item.title} - #{state}, waits for #{waits}")
      end

      read "print each batch and item" do |context|
        batches_of(context).each { |batch| print_batch(context, batch) }
      end

      step "reprint the roadmap file", done: ->(context) { !context.printed_paths.nil? } do |context|
        context[:printed_paths] = context.work.print_roadmap(context.slug)
      end

      outcome :done, offers: "plastic roadmap next %{slug}", because: "the roadmap file matches the rows"
    end
  end
end
