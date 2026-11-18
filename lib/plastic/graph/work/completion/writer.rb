# frozen_string_literal: true

require_relative "check"
require_relative "evidence"
require_relative "review"

module Plastic
  module Graph
    module Work
      module Completion
        # Commits the acceptance attestation and closure together.
        class Writer
          def initialize(databases, retrieval, folder, session:)
            @databases = databases
            @retrieval = retrieval
            @folder = folder
            @session = session
          end

          def close(intent_id)
            intent = @retrieval.intent(intent_id)
            (intent.status == "done") ? raise(Invalid, "intent #{intent_id} is already done") : write_completion(intent_id)
          end

          # An open, in progress, parked or future intent ends as abandoned, with no completion row.
          def abandon(intent_id)
            intent = @retrieval.intent(intent_id)
            return if intent.status == "abandoned"

            write_abandon(intent_id)
            reindex(intent_id)
          end

          private

          def write_abandon(intent_id)
            found = Check.new(@retrieval, intent_id).abandon_problems
            raise Invalid, found.join(" ") if found.any?

            @databases.fetch(:store).transaction do |batch|
              batch.write(:intents, "UPDATE intents SET status = 'abandoned', disposition = :disposition, reason = NULL, closed_at = :now, updated_at = :now " \
                "WHERE intent_id = :intent_id AND origin_id = :origin AND status IN ('open', 'in_progress', 'parked', 'future')",
                now: Plastic.timestamp(@retrieval.clock.now), intent_id:, origin: @retrieval.origin_id, disposition: disposition(intent_id))
            end
          end

          def disposition(intent_id)
            replaced = @retrieval.structure.linking(intent_id).any? { |link| link.supersedes_from_another?(intent_id) }
            replaced ? "superseded" : "cancelled"
          end

          def write_completion(intent_id)
            check = Check.new(@retrieval, intent_id, folder: @folder)
            found = [*check.problems, Review.new(@retrieval, intent_id).problem].compact
            raise Invalid, found.join(" ") if found.any?

            commit_completion(completion_row(intent_id, check))
            reindex(intent_id)
          end

          def reindex(intent_id) = @retrieval.reindex(intent_id)

          def completion_row(intent_id, check)
            criteria = check.criteria
            { intent_id:, at: Plastic.timestamp(@retrieval.clock.now), session_id: @session, judge: "verdict", criteria:,
              evidence: Evidence.new(@retrieval, intent_id).by_criterion(criteria.keys), outcome_sha256: check.outcome_hash }
          end

          def commit_completion(row)
            intent_id, now = row.values_at(:intent_id, :at)
            @databases.fetch(:store).transaction do |batch|
              batch.put(:completions, row, statement: :insert)
              batch.write(:intents, "UPDATE intents SET status = 'done', disposition = 'delivered', closed_at = :now, updated_at = :now " \
                "WHERE intent_id = :intent_id AND origin_id = :origin AND status IN ('open', 'in_progress')",
                now:, intent_id:, origin: @retrieval.origin_id)
            end
          end
        end
      end
    end
  end
end
