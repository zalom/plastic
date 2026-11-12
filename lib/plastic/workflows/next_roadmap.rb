# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/knowledge/roadmap/state"

module Plastic
  module Workflows
    # Finds the first ready item of a roadmap, ranked by batch then item
    # position. With nothing ready, it names what is in flight and blocked.
    class NextRoadmap < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :ready, :ready_id, :open

      gate "no roadmap %{slug}", stops: :failure, pass: ->(context) { !context.retrieval.roadmap(context.slug).nil? }

      def self.items_of(context)
        all = context.retrieval.roadmap_items(context.slug)
        context.position ? all.select { |item| item.batch == context.position.to_i } : all
      end

      def self.states_of(context)
        items_of(context).map { |item| [item, Graph::Knowledge::Roadmap::State.of(item, context.retrieval)] }
      end

      read "find the first ready item, or say what is in the way" do |context|
        states = states_of(context)
        context[:open] = states.reject { |_item, state| %w[done dropped].include?(state) }
        context[:ready] = states.find { |_item, state| state == "ready" }&.first
        context[:ready_id] = context.ready&.item
        print_in_the_way(context, states)
      end

      # What stands between here and delivered: the blocked and in-flight
      # items. A ready item is not in the way, since the outcome's next:
      # line already names it; it is only printed when nothing else is.
      def self.print_in_the_way(context, states)
        blocking = states.reject { |_item, state| %w[done dropped ready].include?(state) }
        blocking = states.select { |_item, state| state == "ready" } if blocking.empty?
        blocking.each { |item, state| context.print("#{item.item}: #{state}") }
      end

      outcome :ready, if: ->(context) { !context.ready.nil? }, offers: "plastic roadmap open %{slug} %{ready_id}",
        because: "item %{ready_id} is ready"
      outcome :delivered, if: ->(context) { context.open.empty? }, offers: "plastic roadmap show %{slug}",
        because: "every item of %{slug} is done or dropped"
      outcome :waiting, offers: "plastic roadmap show %{slug}", because: "no item of %{slug} is ready yet"
    end
  end
end
