# frozen_string_literal: true

require_relative "intent_writer"
require_relative "printer"
require_relative "prints"
require_relative "sync"

module Plastic
  module Graph
    # The write side of the graphs: routine runs, sessions and locks at the
    # home, and the rows and printed files of one store. Every write keeps
    # the store's databases out of its versioning. `session` names the
    # harness session this call runs as, nil when the harness sets none.
    class WorkGraph
      def initialize(databases, folder:, retrieval:, session: nil)
        @databases = databases
        @folder = folder
        @retrieval = retrieval
        @session = session
      end

      # A routine run is call memory, kept off the report.
      def save_routine_run(routine_run)
        row = routine_run.to_h.merge(store: @retrieval.store, subject: routine_run.subject.to_s, session_id: @session)
        @databases.fetch(:home).transaction { |batch| batch.put(:routine_runs, row) }
        routine_run
      end

      # Upserts the session row, keeping `started_at` once it is set.
      def open_session(session_id, harness:, directory:) = stamp(session_id, harness:, directory:)

      # Upserts the session row with the turn's time, keeping `started_at` once it is set.
      def stamp_turn(session_id, harness:, directory:) = stamp(session_id, harness:, directory:, turn: true)

      # The session ended: its time and reason, nothing else.
      def end_session(session_id, reason:)
        home.transaction { |batch| batch.put(:sessions, { session_id:, ended_at: Plastic.now, end_reason: reason }) }
      end

      # The one prose line of a session; a session with no row gets one.
      def write_note(session_id, text)
        home.transaction { |batch| batch.put(:sessions, { session_id:, note: text }) }
      end

      # Writes the lock row of this store, taken and renewed now.
      def take_lock(intent_id, session_id:, mode:)
        now = Plastic.now
        home.transaction { |batch| batch.put(:locks, { store: @retrieval.store, intent_id:, session_id:, mode:, taken_at: now, renewed_at: now }) }
      end

      # Renews every lock row this session names, live or lapsed, and
      # returns how many: the key is the store and the intent, so a lapsed
      # row still naming this session was taken by no one else (review A10).
      def renew_locks(session_id)
        found = home.transaction do |batch|
          batch.add("UPDATE \"locks\" SET \"renewed_at\" = :now WHERE \"session_id\" = :session_id RETURNING session_id",
            now: Plastic.now, session_id:)
        end
        found.sum(&:size)
      end

      # Keeps the store's own databases out of its versioning; a hook calls
      # this before any read, because a read alone can create the files.
      def ignore_databases = @folder.ignore_databases

      def intent_problem(**call) = intents.problem(**call)

      def write_intent(**intent)
        @folder.ignore_databases
        intents.write(**intent)
      end

      def ref_line(ref) = intents.ref_line(ref)

      # Prints store/index.json and every file of one intent; returns the paths written.
      def print_intent(intent_id)
        @folder.ignore_databases
        intent = @retrieval.intent(intent_id)
        sync.printer.print([Prints.index(@retrieval), *Prints.of_intent(@retrieval, intent)])
      end

      def sync_plan(direction, options) = sync.plan(direction, options)

      def sync_apply(plan) = sync.apply(plan)

      private

      def home = @databases.fetch(:home)

      # A session's row keeps the `started_at` it already has; a new row gets one.
      def stamp(session_id, harness:, directory:, turn: false)
        kept = home.row("SELECT started_at FROM sessions WHERE session_id = :session_id", session_id:)
        row = { session_id:, harness:, store: @retrieval.store, directory: }
        row[:last_turn_at] = Plastic.now if turn
        row[:started_at] = Plastic.now unless kept&.fetch("started_at")
        home.transaction { |batch| batch.put(:sessions, row) }
      end

      def intents = (@intents ||= IntentWriter.new(@databases, @retrieval, @folder, session: @session))

      def sync = (@sync ||= Sync.new(folder: @folder, retrieval: @retrieval, databases: @databases))
    end
  end
end
