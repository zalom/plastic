# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/next_pick"
require_relative "../graph/spec"
require_relative "../graph/delivery_action"

module Plastic
  module Workflows
    # Picks the intent this session is working on and offers its next
    # command: the spec, the start, the brief, a failed node, the check or
    # the ready list. Several candidates offer status; none offers a new intent.
    class PickNext < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :next_command, :why, :handoff_text

      read "pick the intent and its next command" do |context|
        context[:next_command], context[:why], context[:handoff_text] = PickNext.offer_for(context, Graph::NextPick.new(context.retrieval, context.session))
      end

      def self.offer_for(context, pick)
        return [nil, "choose the intent to work on", "Inspect plastic status, choose an intent ID, and run plastic intent brief ID."] if pick.ambiguous?
        return ["none", "nothing is open"] if pick.none?

        offer_for_intent(context, pick.intent)
      end

      def self.offer_for_intent(context, intent)
        id = intent.intent_id
        spec = Graph::Spec.new(context.retrieval, id)
        return spec_offer(id, spec) if spec.done_criteria.empty? || spec.open_decisions.any?
        return ["plastic auto start #{id}", "intent #{id} is open"] if intent.status == "open"

        node_offer(context, intent)
      end

      def self.spec_offer(id, spec)
        reason = spec.open_decisions.any? ? "an open decision" : "no done criteria"
        ["plastic intent spec #{id}", "intent #{id} has #{reason}"]
      end

      def self.node_offer(context, intent)
        Graph::DeliveryAction.new(context.retrieval, intent.intent_id).call
      end

      outcome :agent_needed, if: ->(context) { !context.handoff_text.nil? }
      outcome :done, offers: "%{next_command}", because: "%{why}"
    end
  end
end
