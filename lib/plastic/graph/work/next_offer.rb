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

        # What the spec still lacks, or nil when it is clear.
        def self.spec_gap(spec)
          return "an open decision" if spec.open_decisions.any?

          "no done criteria" if spec.done_criteria.empty?
        end

        # The offer for an open intent: auto after the go-ahead row, the owner instruction before it.
        def self.go_ahead_offer(retrieval, id)
          return ["plastic auto #{id}", "intent #{id} is open", nil] if retrieval.approval(id)

          [nil, "the owner must give the go-ahead for intent #{id}", "Ask the owner for the go-ahead. " \
            "Only after the owner gives it, record it with plastic intent approve #{id}."]
        end

        def initialize(retrieval, pick)
          @retrieval = retrieval
          @pick = pick
        end

        # The command, the reason and the handoff text; the handoff is nil
        # unless the next step is the agent's, and then the command is nil.
        def call
          return [nil, "choose the intent to work on", CHOOSE] if @pick.ambiguous?
          return [nil, "nothing is open", nil] if @pick.none?

          for_intent(@pick.intent)
        end

        private

        def for_intent(intent)
          id = intent.intent_id
          gap = gap_of(id)
          return ["plastic intent spec #{id}", "intent #{id} has #{gap}", nil] if gap
          return open_offer(id) if intent.status == "open"

          DeliveryAction.new(@retrieval, id).call
        end

        def gap_of(id) = self.class.spec_gap(Knowledge::Spec.new(@retrieval, id))

        def open_offer(id) = self.class.go_ahead_offer(@retrieval, id)
      end
    end
  end
end
