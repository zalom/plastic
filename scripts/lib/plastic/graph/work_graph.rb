# frozen_string_literal: true

require "forwardable"
require_relative "intent_writer"
require_relative "completion_writer"
require_relative "node_writer"
require_relative "edge_writer"
require_relative "ruling_writer"
require_relative "session_writer"
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
      extend Forwardable

      def_delegators :sessions, :open_session, :stamp_turn, :end_session, :write_note, :take_lock, :renew_locks
      def_delegator :intents, :activate, :activate_intent
      def_delegator :completions, :close, :close_intent
      def_delegator :completions, :evidence, :completion_evidence
      def_delegators :nodes, :add_node, :remove_node, :claim_node, :release_node, :done_node, :fail_node,
        :park_node, :answer_node, :repair_done_node
      def_delegators :edges, :add_edge, :remove_edge
      def_delegators :rulings, :add_ruling

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

      def print_index = sync.printer.print([Prints.index(@retrieval)])

      def sync_plan(direction, options) = sync.plan(direction, options)

      def sync_apply(plan) = sync.apply(plan)

      private

      def completions = (@completions ||= CompletionWriter.new(@databases, @retrieval, @folder, session: @session))

      def sessions = (@sessions ||= SessionWriter.new(@databases.fetch(:home), store: @retrieval.store))

      def intents = (@intents ||= IntentWriter.new(@databases, @retrieval, @folder, session: @session))

      def nodes = (@nodes ||= NodeWriter.new(@databases, @retrieval))

      def edges = (@edges ||= EdgeWriter.new(@databases, @retrieval))

      def rulings = (@rulings ||= RulingWriter.new(@databases, @retrieval, session: @session))

      def sync = (@sync ||= Sync.new(folder: @folder, retrieval: @retrieval, databases: @databases))
    end
  end
end
