# frozen_string_literal: true

module Plastic
  module Graph
    # The write side of the work graph: the routine runs of one store.
    class WorkGraph
      ROUTINE_RUN_UPSERT = <<~SQL
        INSERT INTO routine_runs(store, tool, subject, at, finished, status, facts, next_command, because, exit_code,
          started_at, updated_at)
        VALUES (:store, :tool, :subject, :at, :finished, :status, :facts, :next_command, :because, :exit_code,
          :started_at, :updated_at)
        ON CONFLICT(store, tool, subject) DO UPDATE SET at = excluded.at, finished = excluded.finished,
          status = excluded.status, facts = excluded.facts, next_command = excluded.next_command,
          because = excluded.because, exit_code = excluded.exit_code, started_at = excluded.started_at,
          updated_at = excluded.updated_at
      SQL

      def initialize(database, store:)
        @database = database
        @store = store
      end

      # A routine run is call memory, kept off the report.
      def save_routine_run(routine_run)
        values = routine_run.to_h.merge(subject: routine_run.subject.to_s)
        @database.transaction { |batch| batch.add(ROUTINE_RUN_UPSERT, store: @store, **values) }
        routine_run
      end
    end
  end
end
