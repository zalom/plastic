# frozen_string_literal: true

require_relative "run_record"

module Plastic
  module Harnesses
    # Fills the cost of node runs that ended with none. Claude Code writes the cost of a session in a `cost-state` line when the
    # session stops, after the done command read the record, so the cost is read again later: at the session end and at the
    # intent close. The cost is the harness record's own figure; nothing is priced or estimated. Codex writes no cost, so a Codex
    # run keeps none, and a run whose record is missing or holds no cost yet is left as it was. Docs: docs/usage/node-lifecycle.md.
    class CostFill
      HARNESS = "claude-code"

      def initialize(home:, work:)
        @record = RunRecord.new(home:)
        @work = work
      end

      # Reads again each ended Claude Code run of `runs` with no cost and stores the cost found. Returns the runs that took one.
      def call(runs) = runs.select { |run| run.lacks_cost? && run.harness == HARNESS }.select { |run| fill(run) }

      private

      def fill(run)
        cost = @record.read_run(run).cost_usd
        cost && @work.record_cost(**run.cost_key, cost:)
      end
    end
  end
end
