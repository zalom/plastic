# frozen_string_literal: true

require "digest"
require_relative "evidence"
require_relative "../../knowledge/spec"
require_relative "../../knowledge/outcome"
require_relative "../node"

module Plastic
  module Graph
    module Work
      module Completion
        # Stored prerequisites for delivered closure. Evidence is a judge's attestation.
        class Check
          def initialize(retrieval, intent_id)
            @retrieval = retrieval
            @intent_id = intent_id
          end

          # Each done criterion's key mapped to its text; a criterion repeated word for word counts once.
          def criteria = spec.keyed_criteria.uniq.to_h { |criterion| [criterion.key, criterion.text] }

          def outcome = @retrieval.documents(@intent_id).find { |document| document.path == "outcome.md" }

          def problems = record_problems + verification_problems

          def record_problems
            [criteria_problem, key_problem, decisions_problem, work_problem, outcome_problem].compact
          end

          # The merge and the architecture map are recorded under Verification in outcome.md.
          def verification_problems
            [("Add a line starting Merged: to the Verification section of outcome.md and run plastic sync up." unless merge_recorded?),
              ("Add a line starting Architecture map: to the Verification section of outcome.md and run plastic sync up." unless map_recorded?)].compact
          end

          def abandon_problems = [outcome_problem].compact

          def merge_recorded? = verification.merged?

          def map_recorded? = verification.architecture_map?

          def outcome_hash = Digest::SHA256.hexdigest(outcome.body)

          # The completion fields this check attests, once nothing blocks closure and the evidence answers every criterion.
          def attestation(evidence)
            found = problems
            raise Invalid, found.join(" ") if found.any?

            done = criteria
            Evidence.validate(evidence, done.keys)
            { criteria: done, evidence:, outcome_sha256: outcome_hash }
          end

          private

          def spec = @spec ||= Knowledge::Spec.new(@retrieval, @intent_id)

          def verification = Knowledge::Outcome.new(@retrieval, @intent_id)

          def key_problem
            clashes = spec.keyed_criteria.uniq.group_by(&:key).select { |_key, same| same.size > 1 }.keys
            "Give each done criterion in spec.md its own key; #{clashes.join(", ")} names two different criteria." if clashes.any?
          end

          def criteria_problem = ("Write the done criteria in spec.md and run plastic sync up." if criteria.empty?)

          def decisions_problem = ("Ask the owner to settle the open decisions and record the updated spec." if spec.open_decisions.any?)

          def work_problem
            nodes = live_nodes
            return "Plan at least one work node with plastic node add #{@intent_id} TITLE --criterion TEXT." if nodes.empty?

            unfinished_problem(nodes) || unverified_problem(nodes)
          end

          def unfinished_problem(nodes)
            "Finish every live work node before ending intent #{@intent_id}." unless nodes.all? { |node| node.state == "done" }
          end

          def unverified_problem(nodes)
            return if nodes.all?(&:verified?)

            "Every done node needs a valid judge and nonempty findings. Recheck the work, then use plastic node done #{@intent_id} NODE " \
              "--repair --judge tests|tool|agent|owner --findings TEXT to record the actual verification."
          end

          def live_nodes = @retrieval.nodes(@intent_id).reject { |node| node.state == "removed" }

          def outcome_problem
            "Write a substantive outcome.md in the intent folder and run plastic sync up." if outcome&.body.to_s.gsub(/^\s*#.*$/, "").strip.empty?
          end
        end
      end
    end
  end
end
