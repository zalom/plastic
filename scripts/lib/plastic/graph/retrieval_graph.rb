# frozen_string_literal: true

require "json"
require_relative "../routine_run"
require_relative "session"
require_relative "lock"
require_relative "source"

module Plastic
  module Graph
    # The read side of the graphs: every check reads from here. Every method
    # returns records or plain values. Nothing here writes. A method that
    # takes an intent id reads every intent of the store when given none.
    class RetrievalGraph
      attr_reader :store

      def initialize(databases, store:, origin:)
        @databases = databases
        @store = store
        @origin = origin
      end

      def origin_id = @origin.id

      # The open or last routine run of one tool on one subject.
      def routine_run(tool, subject)
        row = @databases.fetch(:home).row("SELECT * FROM routine_runs WHERE store = :store AND tool = :tool AND " \
          "subject = :subject", store:, tool:, subject: subject.to_s)
        row && RoutineRun.from_row(row, subject)
      end

      # The session row, or nil when it has none.
      def session(session_id)
        row = @databases.fetch(:home).row("SELECT * FROM sessions WHERE session_id = :session_id", session_id:)
        row && Session.from_h(row)
      end

      # The latest other session of this store, by coalesce(last_turn_at, started_at), or nil.
      def previous_session(session_id) = predecessor(session_id)

      # The predecessor a resume reads on a new session or a clear (review
      # A1): the latest session of this store, narrowed to `directory` and
      # preferring `prefer_reason` first, falling back a tier at a time.
      def predecessor(session_id, directory: nil, prefer_reason: nil)
        tiers = [[directory, prefer_reason], [directory, nil], [nil, nil]].uniq
        tiers.filter_map { |tier_directory, reason| predecessor_row(session_id, tier_directory, reason) }
          .first&.then { |row| Session.from_h(row) }
      end

      # Every Lock this session holds, any store.
      def locks_of(session_id)
        @databases.fetch(:home).rows("SELECT * FROM locks WHERE session_id = :session_id", session_id:).map { |row| Lock.from_h(row) }
      end

      # The Lock on one intent of this store, or nil.
      def lock(intent_id)
        row = @databases.fetch(:home).row("SELECT * FROM locks WHERE store = :store AND intent_id = :intent_id", store:, intent_id:)
        row && Lock.from_h(row)
      end

      # The latest RoutineRun of this store whose subject is `intent_id` or
      # whose facts hold it as `intent_id`, by `updated_at`.
      def last_run(intent_id)
        sql = "SELECT * FROM routine_runs WHERE store = :store AND " \
              "(subject = :intent_id OR json_extract(facts, '$.intent_id') = :intent_id) " \
              "ORDER BY updated_at DESC LIMIT 1"
        row = @databases.fetch(:home).row(sql, store:, intent_id:)
        row && RoutineRun.from_row(row, row.fetch("subject"))
      end

      # Intent ids this session touched, most recent first: routine runs of
      # this store with this session id (subject or facts intent_id), and
      # savepoint lines with this session id (review A6: a line sync up
      # rewrote from the file carries no session, so it never counts here).
      def touched(session_id)
        pairs = touched_runs(session_id) + touched_saves(session_id)
        pairs.select { |_at, id| id }.sort_by { |at, _id| at.to_s }.reverse.map(&:last).uniq
      end

      READY_NODES_SQL = <<~SQL
        SELECT * FROM nodes
        WHERE intent_id = :intent_id AND origin_id = :origin
          AND (state IS NULL OR state = '' OR state = 'pending')
          AND NOT EXISTS (
            SELECT 1 FROM edges JOIN nodes AS from_node
              ON from_node.intent_id = edges.intent_id AND from_node.id = edges."from"
            WHERE edges.intent_id = nodes.intent_id AND edges.kind = 'needs' AND edges."to" = nodes.id
              AND from_node.state IS NOT 'done'
          )
        ORDER BY id
      SQL

      # Nodes of `intent_id` ready to run: state nil, empty or pending, with
      # every `needs` edge into them satisfied (graph/edge.rb: `to` waits
      # until `from` is done).
      def ready_nodes(intent_id)
        @databases.fetch(:work).rows(READY_NODES_SQL, intent_id:, origin: origin_id).map { |row| Node.from_h(row) }
      end

      # This installation's intents, in Luhmann order.
      def intents = read(:intents).sort_by(&:segments)

      def intent(intent_id) = intents.find { |intent| intent.intent_id == intent_id }

      def clusters = read(:clusters)

      def documents(intent_id = nil) = read(:documents, intent_id)

      def savepoints(intent_id = nil) = read(:savepoints, intent_id)

      def nodes(intent_id = nil) = read(:nodes, intent_id)

      def edges(intent_id = nil) = read(:edges, intent_id)

      # Kept files with no bytes: a print compares the hash and reads the bytes only to write.
      def kept_files(intent_id = nil) = read(:kept_files, intent_id)

      def kept_file_data(name)
        row = @databases.fetch(:references).row("SELECT hex(data) AS data FROM sqlar WHERE name = :name", name:)
        [row.fetch("data")].pack("H*")
      end

      # The hash of every file printed from the store's rows, by path.
      def printed
        Schema::STORE.flat_map { |key| @databases.fetch(key).rows("SELECT path, sha256 FROM printed") }
          .to_h { |row| row.values_at("path", "sha256") }
      end

      private

      def predecessor_row(session_id, directory, reason)
        conditions = ["store = :store", "session_id != :session_id"]
        conditions << "directory = :directory" if directory
        conditions << "end_reason = :reason" if reason
        sql = "SELECT * FROM sessions WHERE #{conditions.join(" AND ")} ORDER BY COALESCE(last_turn_at, started_at) DESC LIMIT 1"
        @databases.fetch(:home).row(sql, store:, session_id:, directory:, reason:)
      end

      def touched_runs(session_id)
        @databases.fetch(:home).rows("SELECT updated_at AS at, subject, facts FROM routine_runs " \
          "WHERE store = :store AND session_id = :session_id", store:, session_id:).map { |row| [row.fetch("at"), run_intent_id(row)] }
      end

      def touched_saves(session_id)
        @databases.fetch(:work).rows("SELECT at, intent_id FROM savepoints WHERE origin_id = :origin AND session_id = :session_id",
          origin: origin_id, session_id:).map { |row| row.values_at("at", "intent_id") }
      end

      # The intent id a routine run names: the intent_id its facts kept,
      # else its subject, else nil. Intent new takes a title as its subject.
      def run_intent_id(row)
        from_facts = JSON.parse(row.fetch("facts")).fetch("intent_id", nil)
        return from_facts if from_facts

        subject = row.fetch("subject")
        subject.to_s.empty? ? nil : subject
      end

      def read(name, intent_id = nil) = SOURCES.fetch(name).read(@databases, origin: origin_id, intent_id:)
    end
  end
end
