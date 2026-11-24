# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      class Node
        # Stores what the harness's record held of a run on the last run of the node, the run the session that held the node ended.
        # A figure the record did not hold stays nil and the note says why.
        class RunUsage
          SQL = <<~SQL
            UPDATE runs SET worker_session = :worker_session, model = :model, input_tokens = :input_tokens, output_tokens = :output_tokens,
              cache_read_tokens = :cache_read_tokens, cache_write_tokens = :cache_write_tokens, cost_usd = :cost_usd, usage_note = :note
            WHERE intent_id = :intent_id AND node_id = :id AND origin_id = :origin AND session_id = :by AND ended_at IS NOT NULL
              AND number = (SELECT MAX(number) FROM runs WHERE intent_id = :intent_id AND node_id = :id AND origin_id = :origin)
          SQL

          COST_SQL = <<~SQL
            UPDATE runs SET cost_usd = :cost, usage_note = ''
            WHERE intent_id = :intent_id AND node_id = :id AND number = :number AND origin_id = :origin AND ended_at IS NOT NULL AND cost_usd IS NULL
          SQL

          def initialize(databases, retrieval)
            @databases = databases
            @retrieval = retrieval
          end

          # `usage` is a Harnesses::TokenUsage. Returns true when a run took it.
          def call(intent_id:, id:, by:, usage:)
            fields = usage.to_h.merge(worker_session: usage.worker_session.to_s)
            @databases.fetch(:store).transaction { |batch| batch.add(SQL, **fields, intent_id:, id:, by:, origin: @retrieval.origin_id) }.any?
          end

          # Fills the cost of run `number` when the record holds it only now. Returns true when the run took it.
          def cost(intent_id:, id:, number:, cost:)
            @databases.fetch(:store).transaction { |batch| batch.add(COST_SQL, intent_id:, id:, number:, cost:, origin: @retrieval.origin_id) }.any?
          end
        end
      end
    end
  end
end
