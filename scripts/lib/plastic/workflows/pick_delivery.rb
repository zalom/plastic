# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/knowledge/roadmap/state"
require_relative "intent_id_format"

module Plastic
  module Workflows
    # Turns the word `plastic auto` was given into the intent to deliver. A
    # word shaped like an intent id is that intent. Any other word is a
    # roadmap slug: its first item in flight that is not parked and not held
    # by another session's live lock, in batch then item order. With none,
    # it offers a ready item to start, or says the roadmap is delivered or waits.
    class PickDelivery < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :intent_id, :ready_id, :open

      read "forget what an earlier call picked" do |context|
        clear_facts(context, %i[intent_id ready_id open])
      end

      def self.intent_word?(context) = IntentIdFormat::SHAPE.match?(context.id)

      gate "no roadmap %{id}", stops: :failure,
        pass: ->(context) { intent_word?(context) || !context.retrieval.roadmap(context.id).nil? }

      read "pick the intent to deliver" do |context|
        intent_word?(context) ? context[:intent_id] = context.id : pick_item(context)
      end

      def self.pick_item(context)
        items = items_by_state(context)
        context[:open] = items.except("done", "dropped").values.flatten.map(&:item)
        context[:intent_id] = free_item(items["in flight"], context)&.intent_id
        context[:ready_id] = items["ready"]&.first&.item
      end

      # The roadmap's items grouped by state, each group in batch then item order.
      def self.items_by_state(context)
        retrieval = context.retrieval
        retrieval.roadmap_items(context.id).group_by { |item| Graph::Knowledge::Roadmap::State.of(item, retrieval) }
      end

      def self.free_item(items, context) = items&.find { |item| free?(item.intent_id, context) }

      # Neither parked nor held by another session's live lock.
      def self.free?(intent_id, context)
        retrieval = context.retrieval
        lock = retrieval.lock(intent_id)
        held = lock && lock.session_id != context.session && lock.live?
        retrieval.intent(intent_id).status != "parked" && !held
      end

      outcome :intent, if: ->(context) { !context.intent_id.nil? }
      outcome :ready, if: ->(context) { !context.ready_id.nil? }, offers: "plastic roadmap start %{id} %{ready_id}",
        because: "item %{ready_id} is ready"
      outcome :delivered, if: ->(context) { context.open.empty? }, offers: "plastic roadmap show %{id}",
        because: "every item of %{id} is done or dropped"
      outcome :waiting, offers: "plastic roadmap show %{id}", because: "no item of %{id} is free to deliver yet"
    end
  end
end
