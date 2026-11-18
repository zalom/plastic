# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph/knowledge/roadmap/state"

module Plastic
  module Workflows
    module Code
      module Roadmap
        # Picks the roadmap item `roadmap auto` delivers: its first item in flight
        # that is not parked and not held by another session's live claim, in batch
        # then item order. With none, it picks the first ready item to open, or says
        # the roadmap is delivered or waits.
        class Auto < CodeWorkflow
          clear_declarations
          summary "Picks the roadmap item to deliver: the first free item in flight, or the first ready item to open."

          sets :intent_id, :item_id, :open

          read "forget what an earlier call picked" do |context|
            clear_facts(context, %i[intent_id item_id open])
          end

          gate "no roadmap %{slug}", stops: :failure, pass: ->(context) { !context.retrieval.roadmaps.find(context.slug).nil? }

          read "pick the item to deliver" do |context|
            items = items_by_state(context)
            context[:open] = items.except("done", "dropped").values.flatten.map(&:item)
            context[:intent_id] = free_item(items["in flight"], context)&.intent_id
            context[:item_id] = items["ready"]&.first&.item
          end

          # The intent `roadmap auto` would start for the roadmap of `context`, or nil. It writes no fact and
          # raises for no missing roadmap, so a check can ask before the workflow runs.
          def self.intent_for(context)
            return unless context.retrieval.roadmaps.find(context.slug)

            free_item(items_by_state(context)["in flight"], context)&.intent_id
          end

          # The roadmap's items grouped by state, each group in batch then item order.
          def self.items_by_state(context)
            retrieval = context.retrieval
            retrieval.roadmaps.items(context.slug).group_by { |item| Plastic::Graph::Knowledge::Roadmap::State.of(item, retrieval) }
          end

          def self.free_item(items, context) = items&.find { |item| free?(item.intent_id, context) }

          # Neither parked nor holding a node another session claimed.
          def self.free?(intent_id, context)
            retrieval = context.retrieval
            held = retrieval.claimed_nodes.any? { |node| node.intent_id == intent_id && node.claimed_by != context.session && !node.lapsed?(context.now) }
            retrieval.intent(intent_id).status != "parked" && !held
          end

          outcome :intent, if: ->(context) { !context.intent_id.nil? }, because: "an item of %{slug} in flight is free to deliver"
          outcome :ready, if: ->(context) { !context.item_id.nil? }, because: "item %{item_id} of %{slug} is ready"
          outcome :delivered, if: ->(context) { context.open.empty? }, offers: "plastic roadmap show %{slug}",
            because: "every item of %{slug} is done or dropped"
          outcome :waiting, offers: "plastic roadmap auto %{slug}", because: "no item of %{slug} is free to deliver yet"
        end
      end
    end
  end
end
