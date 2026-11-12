# frozen_string_literal: true

require "digest"
require_relative "work_check"
require_relative "../../knowledge/spec"
require_relative "../../knowledge/outcome"
require_relative "../node"

module Plastic
  module Graph
    module Work
      module Completion
        # Stored prerequisites for delivered closure.
        class Check
          def initialize(retrieval, intent_id)
            @retrieval = retrieval
            @intent_id = intent_id
          end

          def criteria = spec.criteria_by_key

          def outcome = @retrieval.documents(@intent_id).find { |document| document.path == "outcome.md" }

          def problems = record_problems + verification_problems

          def record_problems
            [criteria_problem, key_problem, decisions_problem, *WorkCheck.new(@retrieval, @intent_id, criteria.keys).problems, outcome_problem].compact
          end

          def verification_problems = verification.missing_records

          def abandon_problems = [outcome_problem].compact

          def verification = @verification ||= Knowledge::Outcome.new(@retrieval, @intent_id)

          def outcome_hash = Digest::SHA256.hexdigest(outcome.body)

          private

          def spec = @spec ||= Knowledge::Spec.new(@retrieval, @intent_id)

          def key_problem
            clashes = spec.key_clashes.join(", ")
            "Give each done criterion in spec.md its own key; #{clashes} names two different criteria." unless clashes.empty?
          end

          def criteria_problem = ("Write the done criteria in spec.md and run plastic sync up." if criteria.empty?)

          def decisions_problem = ("Ask the owner to settle the open decisions and record the updated spec." if spec.open_decisions.any?)

          def outcome_problem
            "Write a substantive outcome.md in the intent folder and run plastic sync up." if outcome&.body.to_s.gsub(/^\s*#.*$/, "").strip.empty?
          end
        end
      end
    end
  end
end
