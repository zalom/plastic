# frozen_string_literal: true

require "digest"
require_relative "spec"
require_relative "node"

module Plastic
  module Graph
    # Stored prerequisites for delivered closure. Evidence is a judge's attestation.
    class CompletionCheck
      def initialize(retrieval, intent_id)
        @retrieval = retrieval
        @intent_id = intent_id
      end

      def criteria = spec.done_criteria

      def outcome = @retrieval.documents(@intent_id).find { |document| document.path == "outcome.md" }

      def problems
        [criteria_problem, decisions_problem, work_problem, outcome_problem].compact
      end

      def outcome_hash = Digest::SHA256.hexdigest(outcome.body)

      private

      def spec = @spec ||= Spec.new(@retrieval, @intent_id)

      def criteria_problem = ("Write the done criteria in spec.md and run plastic sync up." if criteria.empty?)

      def decisions_problem = ("Ask the owner to settle the open decisions and record the updated spec." if spec.open_decisions.any?)

      def work_problem
        nodes = live_nodes
        return "Plan at least one work node with plastic node add #{@intent_id} TITLE --criterion TEXT." if nodes.empty?
        return "Finish every live work node before ending intent #{@intent_id}." unless nodes.all? { |node| node.state == "done" }
        return nil if nodes.all? { |node| verified?(node) }

        "Every done node needs a valid judge and nonempty findings. Recheck the work, then use plastic node done #{@intent_id} NODE " \
          "--repair --judge tests|tool|agent|owner --findings TEXT to record the actual verification."
      end

      def live_nodes = @retrieval.nodes(@intent_id).reject { |node| node.state == "removed" }

      def verified?(node) = Node::JUDGES.include?(node.judge) && !node.findings.to_s.strip.empty?

      def outcome_problem
        "Write a substantive outcome.md in the intent folder and run plastic sync up." if outcome&.body.to_s.gsub(/^\s*#.*$/, "").strip.empty?
      end
    end
  end
end
