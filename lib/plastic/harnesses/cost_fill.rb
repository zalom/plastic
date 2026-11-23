# frozen_string_literal: true

require_relative "records/claude"
require_relative "run_record"

module Plastic
  module Harnesses
    # Fills the cost of node runs that ended with none. Claude Code writes the cost of a session in a `cost-state` line when the
    # session stops, after the done command read the record, so the cost is read again later: at the session end and at the
    # intent close. The cost is the harness record's own figure; nothing is priced or estimated.
    #
    # Only a run of a main session can take a cost, and a headless worker started with `claude -p` is one. Claude Code writes the
    # `cost-state` of a session in its main file, never in a subagent's, so a run a subagent worked stays with none. Codex writes
    # no cost, so a Codex run keeps none. A run whose record is missing, holds no cost yet, or cannot tell the run's share of the
    # session total is left as it was. Docs: docs/usage/node-lifecycle.md.
    class CostFill
      HARNESS = "claude-code"
      SUBAGENT = "agent-"

      def initialize(home:, work:)
        @claude = Records::Claude.new(home:)
        @work = work
      end

      # Reads again each ended main-session Claude Code run of `runs` with no cost and stores the cost found. Reads each session's
      # file once. Returns the runs that took a cost.
      def call(runs) = self.class.candidates(runs).group_by(&:session_id).flat_map { |session, group| fill(session, group) }

      def self.candidates(runs) = runs.select { |run| run.lacks_cost? && run.harness == HARNESS && !run.worker_session.to_s.start_with?(SUBAGENT) }

      private

      def fill(session, group)
        costs = @claude.costs(session:, runs: group.map { |run| [run.window(RunRecord::END_SECOND), run.claim_text] })
        group.zip(costs).select { |run, cost| cost && @work.record_cost(**run.cost_key, cost:) }.map(&:first)
      end
    end
  end
end
