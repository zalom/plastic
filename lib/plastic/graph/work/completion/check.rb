# frozen_string_literal: true

require "digest"
require_relative "work_check"
require_relative "../../knowledge/spec"
require_relative "../../knowledge/outcome"
require_relative "../../rows/node"
require_relative "../../../layout"

module Plastic
  module Graph
    module Work
      module Completion
        # Stored prerequisites for delivered closure.
        class Check
          def initialize(retrieval, intent_id, folder: nil)
            @retrieval = retrieval
            @intent_id = intent_id
            @folder = folder
          end

          def criteria = spec.criteria_by_key

          def outcome = @retrieval.documents(@intent_id).find { |document| document.path == Layout.name(:outcome) }

          def problems = record_problems + verification_problems

          def record_problems
            [criteria_problem, key_problem, decisions_problem, *WorkCheck.new(@retrieval, @intent_id, criteria.keys).problems, outcome_problem].compact
          end

          def verification_problems = verification.missing_records

          def abandon_problems = [outcome_problem, reason_problem].compact

          def verification = @verification ||= Knowledge::Outcome.new(@retrieval, @intent_id, folder: @folder)

          def outcome_hash = Digest::SHA256.hexdigest(outcome.body)

          private

          def spec = @spec ||= Knowledge::Spec.new(@retrieval, @intent_id)

          def key_problem
            clashes = spec.key_clashes.join(", ")
            "Give each done criterion in spec.md its own key; #{clashes} names two different criteria." unless clashes.empty?
          end

          def criteria_problem = ("Write the done criteria with plastic intent spec #{@intent_id} --from FILE." if criteria.empty?)

          def decisions_problem = ("Ask the owner to settle the open decisions and record the updated spec." if spec.open_decisions.any?)

          def outcome_problem
            "Write the summary of outcome.md with plastic intent outcome #{@intent_id} --from FILE." if outcome&.body.to_s.gsub(/^\s*#.*$/, "").strip.empty?
          end

          def reason_problem
            return if verification.abandoned?

            found = verification.rejected("Abandoned")
            quoted = found ? "outcome.md says '#{found}', which is not an abandon reason in the form #{Knowledge::OutcomeForm.shown_forms("Abandoned")}. " : ""
            "#{quoted}Record why intent #{@intent_id} is dropped with #{Knowledge::OutcomeForm.note_commands("Abandoned", @intent_id)}."
          end
        end
      end
    end
  end
end
