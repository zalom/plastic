# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/knowledge/roadmap/state"

module Plastic
  module Workflows
    # Prints each batch with its goal and done criteria, then each item with
    # its derived state, and reprints roadmaps/SLUG.md from rows.
    class ShowRoadmap < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :printed_paths

      gate "no roadmap %{slug}", stops: :failure, pass: ->(context) { !context.retrieval.roadmap(context.slug).nil? }

      def self.batches_of(context)
        all = context.retrieval.batches(context.slug)
        position = context.position
        position ? all.select { |row| row.position == position.to_i } : all
      end

      def self.print_batch(context, batch)
        context.print(["batch #{batch.position}: #{batch.title}", batch.goal].compact.reject(&:empty?).join(" - "))
        batch.done_lines.each { |line| context.print("  done: #{line}") }
        items_of(context, batch).each { |item| print_item(context, item) }
      end

      def self.items_of(context, batch)
        context.retrieval.roadmap_items(context.slug).select { |item| item.batch == batch.position }
      end

      def self.print_item(context, item)
        retrieval = context.retrieval
        state = Graph::Knowledge::Roadmap::State.of(item, retrieval)
        name = item.item
        waits = waits_of(retrieval.roadmap_edges(context.slug), name)
        context.print("item #{name}: #{item.title} - #{state}, waits for #{waits}")
      end

      def self.waits_of(edges, name)
        from = edges.select { |edge| edge.to == name }.map(&:from)
        from.empty? ? "nothing" : from.join(" ")
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
