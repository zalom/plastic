# frozen_string_literal: true

require_relative "check"
require_relative "evidence"
require_relative "review"

module Plastic
  module Graph
    module Work
      module Completion
        # Commits the acceptance attestation and closure together, then releases the lock.
        class Writer
          def initialize(databases, retrieval, folder, session:)
            @databases = databases
            @retrieval = retrieval
            @folder = folder
            @session = session
          end

          def close(intent_id)
            intent = @retrieval.intent(intent_id)
            (intent.status == "done") ? retry_close(intent_id) : write_completion(intent_id)
            release_lock(intent_id)
          end

          # An open, active, parked or future intent ends as abandoned, with no completion row.
          def abandon(intent_id)
            intent = @retrieval.intent(intent_id)
            write_abandon(intent_id) unless intent.status == "abandoned"
            release_lock(intent_id)
          end

          private

          def retry_close(intent_id)
            raise Invalid, "intent #{intent_id} is already done" unless @retrieval.lock(intent_id)
          end

          def write_abandon(intent_id)
            found = Check.new(@retrieval, intent_id).abandon_problems
            raise Invalid, found.join(" ") if found.any?

            @databases.fetch(:work).transaction do |batch|
              batch.write(:intents, "UPDATE intents SET status = 'abandoned', disposition = :disposition, closed_at = :now, updated_at = :now " \
                "WHERE intent_id = :intent_id AND origin_id = :origin AND status IN ('open', 'active', 'parked', 'future')",
                now: Plastic.now, intent_id:, origin: @retrieval.origin_id, disposition: disposition(intent_id))
            end
          end

          def disposition(intent_id)
            replaced = @retrieval.linking(intent_id).any? do |link|
              link.kind == "supersedes" && link.to_ref == intent_id && link.from_intent_id != intent_id
            end
            replaced ? "superseded" : "cancelled"
          end

          def write_completion(intent_id)
            check = Check.new(@retrieval, intent_id)
            found = [*check.problems, Review.new(@retrieval, intent_id).problem].compact
            raise Invalid, found.join(" ") if found.any?

            commit_completion(completion_row(intent_id, check))
          end

          def completion_row(intent_id, check)
            criteria = check.criteria
            { intent_id:, at: Plastic.now, session_id: @session, judge: "verdict", criteria:,
              evidence: Evidence.new(@retrieval, intent_id).by_criterion(criteria.keys), outcome_sha256: check.outcome_hash }
          end

          def commit_completion(row)
            intent_id, now = row.values_at(:intent_id, :at)
            @databases.fetch(:work).transaction do |batch|
              batch.put(:completions, row, statement: :insert)
              batch.write(:intents, "UPDATE intents SET status = 'done', disposition = 'delivered', closed_at = :now, updated_at = :now " \
                "WHERE intent_id = :intent_id AND origin_id = :origin AND status IN ('open', 'active')",
                now:, intent_id:, origin: @retrieval.origin_id)
            end
          end

          def release_lock(intent_id)
            lock = @retrieval.lock(intent_id)
            delete_lock(lock) if lock && !(lock.live? && lock.session_id != @session)
          end

          def delete_lock(lock)
            @databases.fetch(:local).transaction do |batch|
              batch.write(:locks, "DELETE FROM locks WHERE store = :store AND intent_id = :intent_id AND session_id = :session_id AND renewed_at = :renewed_at",
                store: @retrieval.store, **lock.to_h.slice(:intent_id, :session_id, :renewed_at))
            end
          end
        end
      end
    end
  end
end
