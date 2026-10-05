# frozen_string_literal: true

require_relative "delivery_action"
require_relative "../knowledge/spec"

module Plastic
  module Graph
    module Work
      # The next command of one store for the intent its pick names: the
      # spec, the start, the brief, a failed node, the check or the ready
      # list. Several candidates hand the choice to the agent; none offers
      # nothing. `plastic next` and `plastic graph resume` both read it.
      class NextOffer
        CHOOSE = "Inspect plastic status, choose an intent ID, and run plastic intent brief ID."

        def initialize(retrieval, pick)
          @retrieval = retrieval
          @pick = pick
        end

        # The command, the reason and the handoff text; the handoff is nil
        # unless the next step is the agent's, and then the command is nil.
        def call
          return [nil, "choose the intent to work on", CHOOSE] if @pick.ambiguous?
          return ["none", "nothing is open", nil] if @pick.none?

          for_intent(@pick.intent)
        end

        private

        def for_intent(intent)
          id = intent.intent_id
          spec = Knowledge::Spec.new(@retrieval, id)
          return spec_offer(id, spec) if spec.done_criteria.empty? || spec.open_decisions.any?
          return ["plastic auto start #{id}", "intent #{id} is open", nil] if intent.status == "open"

          DeliveryAction.new(@retrieval, id).call
        end

        def spec_offer(id, spec)
          reason = spec.open_decisions.any? ? "an open decision" : "no done criteria"
          ["plastic intent spec #{id}", "intent #{id} has #{reason}", nil]
        end
      end
    end
  end
end
