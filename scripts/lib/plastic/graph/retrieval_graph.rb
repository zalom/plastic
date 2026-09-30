# frozen_string_literal: true

require_relative "../routine_run"

module Plastic
  module Graph
    # The read side of the graphs: every check reads from here. Every method
    # returns records or plain values. Nothing here writes.
    class RetrievalGraph
      attr_reader :store

      def initialize(databases, store:)
        @databases = databases
        @store = store
      end

      # The open or last routine run of one tool on one subject.
      def routine_run(tool, subject)
        row = work.row("SELECT * FROM routine_runs WHERE store = :store AND tool = :tool AND subject = :subject",
          store:, tool:, subject: subject.to_s)
        row && RoutineRun.from_row(row, subject)
      end

      private

      def work = @databases.fetch(:work)
    end
  end
end
