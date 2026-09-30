# frozen_string_literal: true

require_relative "intent_writer"
require_relative "printer"
require_relative "prints"
require_relative "sync"

module Plastic
  module Graph
    # The write side of the graphs: routine runs at the home, and the rows
    # and printed files of one store. Every write keeps the store's
    # databases out of its versioning.
    class WorkGraph
      def initialize(databases, folder:, retrieval:)
        @databases = databases
        @folder = folder
        @retrieval = retrieval
      end

      # A routine run is call memory, kept off the report.
      def save_routine_run(routine_run)
        row = routine_run.to_h.merge(store: @retrieval.store, subject: routine_run.subject.to_s)
        @databases.fetch(:home).transaction { |batch| batch.put(:routine_runs, row, count: false) }
        routine_run
      end

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

      def sync_plan(direction, **options) = sync.plan(direction, **options)

      def sync_apply(plan) = sync.apply(plan)

      private

      def intents = (@intents ||= IntentWriter.new(@databases, @retrieval, @folder))

      def sync = (@sync ||= Sync.new(folder: @folder, retrieval: @retrieval, databases: @databases))
    end
  end
end
