# frozen_string_literal: true

require_relative "../routine_run"
require_relative "session"
require_relative "lock"

module Plastic
  module Graph
    # The read side of the home's `sessions`, `locks` and `routine_runs`
    # tables for one store, and the savepoint lines a session wrote.
    class SessionReader
      PREDECESSOR_SQL = <<~SQL
        SELECT * FROM sessions
        WHERE store = :store AND session_id != :session_id
          AND (:directory IS NULL OR directory = :directory) AND (:reason IS NULL OR end_reason = :reason)
        ORDER BY COALESCE(last_turn_at, started_at) DESC LIMIT 1
      SQL

      # A routine run names the intent_id its facts kept, else its subject;
      # intent new takes a title as its subject and keeps the id in its facts.
      TOUCHED_RUNS_SQL = <<~SQL
        SELECT updated_at AS at, COALESCE(json_extract(facts, '$.intent_id'), NULLIF(subject, '')) AS intent_id
        FROM routine_runs WHERE store = :store AND session_id = :session_id
      SQL

      TOUCHED_SAVES_SQL = "SELECT at, intent_id FROM savepoints WHERE origin_id = :origin AND session_id = :session_id"

      LAST_RUN_SQL = <<~SQL
        SELECT * FROM routine_runs WHERE store = :store
          AND (subject = :intent_id OR json_extract(facts, '$.intent_id') = :intent_id)
        ORDER BY updated_at DESC LIMIT 1
      SQL

      def initialize(databases, store:, origin:)
        @databases = databases
        @store = store
        @origin = origin
      end

      # The open or last routine run of one tool on one subject.
      def routine_run(tool, subject)
        row = home.row("SELECT * FROM routine_runs WHERE store = :store AND tool = :tool AND subject = :subject",
          store: @store, tool:, subject: subject.to_s)
        row && RoutineRun.from_row(row, subject)
      end

      # The session row, or nil when it has none.
      def session(session_id)
        row = home.row("SELECT * FROM sessions WHERE session_id = :session_id", session_id:)
        row && Session.from_h(row)
      end

      # The latest other session of this store, by coalesce(last_turn_at, started_at), or nil.
      def previous_session(session_id) = predecessor(session_id)

      # The predecessor a resume reads on a new session or a clear (review
      # A1): the latest session of this store, narrowed to `directory` and
      # preferring `prefer_reason` first, falling back a tier at a time.
      def predecessor(session_id, directory: nil, prefer_reason: nil)
        tiers = [[directory, prefer_reason], [directory, nil], [nil, nil]].uniq
        row = tiers.lazy.filter_map { |place, reason| home.row(PREDECESSOR_SQL, store: @store, session_id:, directory: place, reason:) }.first
        row && Session.from_h(row)
      end

      # Every Lock this session holds, any store.
      def locks_of(session_id)
        home.rows("SELECT * FROM locks WHERE session_id = :session_id", session_id:).map { |row| Lock.from_h(row) }
      end

      # The Lock on one intent of this store, or nil.
      def lock(intent_id)
        row = home.row("SELECT * FROM locks WHERE store = :store AND intent_id = :intent_id", store: @store, intent_id:)
        row && Lock.from_h(row)
      end

      # The latest RoutineRun of this store whose subject is `intent_id` or
      # whose facts hold it as `intent_id`, by `updated_at`.
      def last_run(intent_id)
        row = home.row(LAST_RUN_SQL, store: @store, intent_id:)
        row && RoutineRun.from_row(row, row.fetch("subject"))
      end

      # Intent ids this session touched, most recent first: routine runs of
      # this store with this session id, and savepoint lines with this
      # session id (review A6: a line sync up rewrote from the file carries
      # no session, so it never counts here).
      def touched(session_id)
        rows = home.rows(TOUCHED_RUNS_SQL, store: @store, session_id:) +
          @databases.fetch(:work).rows(TOUCHED_SAVES_SQL, origin: @origin.id, session_id:)
        rows.map { |row| row.values_at("at", "intent_id") }.select(&:last).sort_by { |pair| pair.first.to_s }.reverse.map(&:last).uniq
      end

      private

      def home = @databases.fetch(:home)
    end
  end
end
