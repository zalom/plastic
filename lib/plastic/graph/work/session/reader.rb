# frozen_string_literal: true

require_relative "../../../command_run"
require_relative "../session"
require_relative "touched"

module Plastic
  module Graph
    module Work
      class Session
        # The read side of the local database's `sessions` and `command_runs`
        # tables for one store, and the work log lines a session wrote.
        class Reader
          PREDECESSOR_SQL = <<~SQL
            SELECT * FROM sessions
            WHERE store = :store AND session_id != :session_id
              AND (:directory IS NULL OR directory = :directory) AND (:reason IS NULL OR end_reason = :reason)
            ORDER BY COALESCE(last_turn_at, started_at) DESC LIMIT 1
          SQL

          LAST_RUN_SQL = <<~SQL
            SELECT * FROM command_runs WHERE store = :store
              AND (subject = :intent_id OR json_extract(facts, '$.intent_id') = :intent_id)
            ORDER BY updated_at DESC LIMIT 1
          SQL

          SESSIONS_ON_SQL = <<~SQL
            SELECT DISTINCT session_id FROM command_runs WHERE store = :store AND session_id IS NOT NULL AND updated_at >= :since
              AND (subject = :intent_id OR json_extract(facts, '$.intent_id') = :intent_id)
          SQL

          def initialize(databases, store:, origin:)
            @databases = databases
            @store = store
            @origin = origin
          end

          # The open or last command run of one tool on one subject.
          def command_run(tool, subject)
            row = local.row("SELECT * FROM command_runs WHERE store = :store AND tool = :tool AND subject = :subject",
              store: @store, tool:, subject: subject.to_s)
            row && CommandRun.from_row(row, subject)
          end

          # The session row, or nil when it has none.
          def session(session_id)
            row = local.row("SELECT * FROM sessions WHERE session_id = :session_id", session_id:)
            row && Session.from_h(row)
          end

          # The latest other session of this store, by coalesce(last_turn_at, started_at), or nil.
          def previous_session(session_id) = predecessor(session_id)

          # The predecessor a resume reads on a new session or a clear (review
          # A1): the latest session of this store, narrowed to `directory` and
          # preferring `prefer_reason` first, falling back a tier at a time.
          def predecessor(session_id, directory: nil, prefer_reason: nil)
            tiers = [[directory, prefer_reason], [directory, nil], [nil, nil]].uniq
            row = tiers.lazy.filter_map { |place, reason| local.row(PREDECESSOR_SQL, store: @store, session_id:, directory: place, reason:) }.first
            row && Session.from_h(row)
          end

          # The latest CommandRun of this store whose subject is `intent_id` or
          # whose facts hold it as `intent_id`, by `updated_at`.
          def last_run(intent_id)
            row = local.row(LAST_RUN_SQL, store: @store, intent_id:)
            row && CommandRun.from_row(row, row.fetch("subject"))
          end

          # The sessions whose command runs of this store named `intent_id` at or after `since`, a stored time.
          def sessions_on(intent_id, since:) = local.rows(SESSIONS_ON_SQL, store: @store, intent_id:, since:).map { |row| row.fetch("session_id") }

          # Intent ids this session touched, most recent first.
          def touched(session_id) = Touched.new(@databases, store: @store, origin: @origin).call(session_id)

          private

          def local = @databases.fetch(:local)
        end
      end
    end
  end
end
