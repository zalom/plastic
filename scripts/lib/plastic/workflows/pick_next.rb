# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/next_pick"
require_relative "../graph/spec"

module Plastic
  module Workflows
    # Picks the intent this session is working on and offers its next
    # command: the spec, the start, the brief, a failed node, the check or
    # the ready list. Several candidates offer status; none offers a new intent.
    class PickNext < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :next_command, :why

      read "pick the intent and its next command" do |context|
        context[:next_command], context[:why] = PickNext.offer_for(context, Graph::NextPick.new(context.retrieval, context.session))
      end

      def self.offer_for(context, pick)
        return ["plastic status", "several intents stand out; narrow it down first"] if pick.ambiguous?
        return ["plastic intent new TITLE", "nothing is open"] if pick.none?

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
        live = context.retrieval.nodes(intent.intent_id).reject { |node| node.state == "removed" }
        NODE_OFFERS.fetch(live_state(live)).call(intent)
      end

      LIVE_STATE_RULES = [
        [:brief, ->(states) { states.empty? || states.include?("parked") }],
        [:show, ->(states) { states.include?("failed") }],
        [:check, ->(states) { states.all? { |state| state == "done" } }]
      ].freeze

      def self.live_state(live)
        states = live.map(&:state)
        rule = LIVE_STATE_RULES.find { |_name, matches| matches.call(states) }
        rule ? rule.first : :ready
      end

      def self.brief_offer(intent)
        id = intent.intent_id
        ["plastic intent brief #{id}", "intent #{id} has no nodes or a parked one"]
      end

      def self.show_offer(intent)
        id = intent.intent_id
        ["plastic graph show #{id}", "intent #{id} has a failed node"]
      end

      def self.check_offer(intent)
        id = intent.intent_id
        ["plastic graph check #{id}", "every live node of intent #{id} is done"]
      end

      def self.ready_offer(intent)
        id = intent.intent_id
        ["plastic graph ready #{id}", "intent #{id} has nodes left to claim"]
      end

      NODE_OFFERS = {
        brief: ->(intent) { brief_offer(intent) },
        show: ->(intent) { show_offer(intent) },
        check: ->(intent) { check_offer(intent) },
        ready: ->(intent) { ready_offer(intent) }
      }.freeze

      outcome :done, offers: "%{next_command}", because: "%{why}"
    end
  end
end
