# frozen_string_literal: true

require_relative "delivery_action"
require_relative "../knowledge/spec"

module Plastic
  module Graph
    module Work
      # The next command of one store for the intent its pick names: the
      # start of an approved open intent, the spec, the go-ahead, the brief, a failed node, the check or the ready
      # list. Several candidates hand the choice to the agent; none offers
      # nothing. `plastic next` and `plastic graph resume` both read it.
      class NextOffer
        CHOOSE = "Inspect plastic status, choose an intent ID, and run plastic intent brief ID."

        # What the spec still lacks, or nil when it is clear.
        def self.spec_gap(spec)
          return "an open decision" if spec.open_decisions.any?

          "no done criteria" if spec.done_criteria.empty?
        end

        # The offer for an open intent: intent start after the go-ahead row, the owner instruction before it.
        def self.go_ahead_offer(retrieval, id)
          return ["plastic intent start #{id}", "intent #{id} is open", nil] if retrieval.structure.approval(id)

          [nil, "the owner must give the go-ahead for intent #{id}", "Ask the owner for the go-ahead. " \
            "Only after the owner gives it, record it with plastic intent approve #{id}."]
        end

        def initialize(retrieval, pick, work: :general)
          @retrieval = retrieval
          @pick = pick
          @work = work
        end

        # The command, the reason and the handoff text; the handoff is nil
        # unless the next step is the agent's, and then the command is nil.
        def call
          return [nil, "choose the intent to work on", CHOOSE] if @pick.ambiguous?
          return none_offer if @pick.none?

          for_intent(@pick.intent)
        end

        private

        def none_offer
          return [nil, "nothing is open", nil] if @pick.blocked.empty?

          id, needed = @pick.blocked.first
          [nil, "nothing is ready: intent #{id} waits on #{needed.map { |each| "intent #{each}" }.join(", ")}", nil]
        end

        def for_intent(intent)
          id = intent.intent_id
          open = intent.status == "open"
          gap = gap_of(id) unless open && approved?(id)
          return ["plastic intent spec #{id}", "intent #{id} has #{gap}", nil] if gap
          return self.class.go_ahead_offer(@retrieval, id) if open

          DeliveryAction.new(@retrieval, id, work: @work).call
        end

        def gap_of(id) = self.class.spec_gap(Knowledge::Spec.new(@retrieval, id))

        def approved?(id) = !@retrieval.structure.approval(id).nil?
      end
    end
  end
end
