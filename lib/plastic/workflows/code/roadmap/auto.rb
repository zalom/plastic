# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph/knowledge/roadmap/state"

module Plastic
  module Workflows
    module Code
      module Roadmap
        # Picks the roadmap item `roadmap auto` delivers: its first free item with an
        # intent to start, in flight first and then ready, in batch then item order. A
        # free item is not parked, and no other session holds it with a live claim or
        # ran a command on its intent within 15 minutes. With none, it picks the first
        # ready item with no intent to open, or says the roadmap is delivered or waits.
        class Auto < CodeWorkflow
          clear_declarations
          summary "Picks the roadmap item to deliver: the first free item with an intent to start, or the first ready item to open."

          sets :intent_id, :item_id, :open, :waiting

          read "forget what an earlier call picked" do |context|
            clear_facts(context, %i[intent_id item_id open waiting])
          end

          gate "no roadmap %{slug}", stops: :failure, pass: ->(context) { !context.retrieval.roadmaps.find(context.slug).nil? }

          read "pick the item to deliver" do |context|
            items = items_by_state(context)
            context[:open] = items.except("done", "dropped").values.flatten.map(&:item)
            context[:waiting] = context.open.join(", ")
            context[:intent_id] = free_item(startable(items), context)&.intent_id
            context[:item_id] = items.fetch("ready", []).find { |item| item.intent_id.nil? }&.item
          end

          # The intent `roadmap auto` would start for the roadmap of `context`, or nil. It writes no fact and
          # raises for no missing roadmap, so a check can ask before the workflow runs.
          def self.intent_for(context)
            return unless context.retrieval.roadmaps.find(context.slug)

            free_item(startable(items_by_state(context)), context)&.intent_id
          end

          # The items with an intent to start: those in flight, then the ready ones whose intent is future.
          def self.startable(items) = items.fetch("in flight", []) + items.fetch("ready", []).select(&:intent_id)

          # The roadmap's items grouped by state, each group in batch then item order.
          def self.items_by_state(context)
            retrieval = context.retrieval
            retrieval.roadmaps.items(context.slug).group_by { |item| Plastic::Graph::Knowledge::Roadmap::State.of(item, retrieval) }
          end

          def self.free_item(items, context) = items.find { |item| free?(item.intent_id, context) }

          # Not parked, and not held by another session.
          def self.free?(intent_id, context) = context.retrieval.intent(intent_id).status != "parked" && !held?(intent_id, context)

          # Another session claimed a node of the intent and renewed it, or ran a command on the intent, within 15 minutes.
          def self.held?(intent_id, context)
            retrieval, session, now = context.retrieval, context.session, context.now
            claimed = retrieval.claimed_nodes.any? { |node| node.intent_id == intent_id && node.claimed_by != session && !node.lapsed?(now) }
            claimed || (retrieval.sessions_on(intent_id, since: Plastic.timestamp(now - Plastic::Graph::Work::Node::LAPSE)) - [session]).any?
          end

          outcome :intent, if: ->(context) { !context.intent_id.nil? }, because: "an item of %{slug} in flight is free to deliver"
          outcome :ready, if: ->(context) { !context.item_id.nil? }, because: "item %{item_id} of %{slug} is ready"
          outcome :delivered, if: ->(context) { context.open.empty? }, offers: "plastic roadmap show %{slug}",
            because: "every item of %{slug} is done or dropped"
          outcome :waiting, offers: "plastic roadmap show %{slug}", because: "no item of %{slug} is free to deliver yet; it waits on %{waiting}"
        end
      end
    end
  end
end
