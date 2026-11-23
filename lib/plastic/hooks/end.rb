# frozen_string_literal: true

require_relative "../cli/hook"
require_relative "../graph"
require_relative "../cli/wiring"
require_relative "../harnesses/cost_fill"

module Plastic
  module Hooks
    # SessionEnd: sets the session's end time and the reason the event names, fills the cost of its runs that have none,
    # then releases its node and driver claims.
    # With backup.daily on, it then takes the end-of-day backup of every store.
    class End < CLI::Hook
      changes(local: "The end time and the reason are written to the session row", work: "The cost of a run of the session that has none is filled when the harness record holds it, and the node claims and the driver claims of the session are released", backups: "With backup.daily on, every store takes its end-of-day backup, which replaces the earlier one of the day")

      def respond(event)
        return no_session unless session_id

        work = graphs.work
        work.end_session(session_id, reason: event[:reason])
        fill_costs
        work.release_claims(session_id)
        nil
      end

      private

      # The cost of a run is written by Claude Code when the session stops, after the done command read the record.
      def graphs = (@graphs ||= Wiring.graphs(home: scope.plastic_home, store: scope.slug, session: session_id, clock: environment.clock))

      def fill_costs
        runs = graphs.retrieval.structure.runs.select { |run| run.session_id == session_id }
        Harnesses::CostFill.new(home: environment.home.to_s, work: graphs.work).call(runs)
      end

      def back_up_the_day = CLI::DayBackup.new(environment).back_up(:end_session)

      def no_session
        environment.err.puts "plastic hook: the event names no session; nothing recorded"
        nil
      end
    end
  end
end
