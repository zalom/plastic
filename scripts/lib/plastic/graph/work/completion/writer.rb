# frozen_string_literal: true

require_relative "check"
require_relative "evidence"

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

          def evidence(intent_id, path, criteria)
            Evidence.read(@folder, @retrieval.intent(intent_id), path, criteria)
          end

          def close(intent_id, judge:, evidence:)
            intent = @retrieval.intent(intent_id)
            write_completion(intent_id, judge, evidence) unless intent.status == "done"
            release_lock(intent_id)
          end

          private

          def write_completion(intent_id, judge, evidence)
            check = Check.new(@retrieval, intent_id)
            raise Invalid, check.problems.join(" ") if check.problems.any?

            Evidence.validate(evidence, check.criteria)
            now = Plastic.now
            row = { intent_id:, at: now, session_id: @session, judge:, criteria: check.criteria, evidence:,
                    outcome_sha256: check.outcome_hash }
            commit_completion(row)
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
            completion = @retrieval.completion(intent_id)
            lock = @retrieval.lock(intent_id)
            return unless completion && lock
            return if lock.live? && lock.session_id != completion.fetch("session_id")

            @databases.fetch(:local).transaction do |batch|
              batch.write(:locks, "DELETE FROM locks WHERE store = :store AND intent_id = :intent_id AND session_id = :session_id AND renewed_at = :renewed_at",
                store: @retrieval.store, intent_id:, session_id: lock.session_id, renewed_at: lock.renewed_at)
            end
          end
        end
      end
    end
  end
end
