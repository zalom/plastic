# frozen_string_literal: true

require "forwardable"
require_relative "knowledge/roadmap/item_start"
require_relative "knowledge/backup/store_backups"
require_relative "printer"
require_relative "prints"
require_relative "knowledge/sync/preview"
require_relative "work/writers"
require_relative "knowledge/intent/noter"

module Plastic
  module Graph
    # The write side of the graphs: routine runs, sessions and locks at the
    # home, and the rows and printed files of one store. Every write keeps
    # the store's databases out of its versioning. `session` names the
    # harness session this call runs as, nil when the harness sets none.
    class WorkGraph
      extend Forwardable

      def_delegators "@writers.sessions", :open_session, :stamp_turn, :end_session, :write_note, :take_lock, :renew_locks
      def_delegator "@writers.intents", :activate, :activate_intent
      def_delegator "@writers.intents", :open_problem, :open_intent_problem
      def_delegator "@writers.intents", :problem, :intent_problem
      def_delegator "@writers.intents", :ref_line
      def_delegator "@writers.revisions", :change, :revision
      def_delegator "@writers.revisions", :write, :revise_intent
      def_delegator :noter, :problem, :note_problem
      def_delegator :noter, :write, :note_intent
      def_delegator "@writers.completions", :close, :close_intent
      def_delegator "@writers.completions", :abandon, :abandon_intent
      def_delegators "@writers.nodes", :add_node, :remove_node, :claim_node, :release_node, :done_node, :fail_node,
        :ask_node, :impede_node, :resolve_node
      def_delegator "@writers.approvals", :approve, :approve_intent
      def_delegators "@writers.verdicts", :add_verdict, :rounds_left?
      def_delegators "@writers.edges", :add_edge, :remove_edge
      def_delegators "@writers.rulings", :add_ruling
      def_delegators "@writers.links", :add_link, :remove_link
      def_delegator "@writers.links", :target_problem, :link_target_problem
      def_delegator "@writers.links", :refusal, :link_refusal
      def_delegators "@writers.roadmaps", :create_roadmap, :write_batch, :add_item, :start_item, :drop_item, :remove_roadmap_edge, :add_log
      def_delegator "@writers.sync", :plan, :sync_plan
      def_delegator "@writers.sync", :apply, :sync_apply
      # The snapshot restores exact bytes; printing live rows would replace them.
      # Returns [ok, problem, kind]; kind is :failure, nil on success. Restores the saved directory.
      def_delegator "@writers.archives", :restore, :restore_intent

      def initialize(databases, folder:, retrieval:, session: nil)
        @databases = databases
        @folder = folder
        @retrieval = retrieval
        @writers = Work::Writers.new(databases, retrieval, folder, session)
      end

      # A routine run is call memory, kept off the report.
      def save_routine_run(routine_run)
        row = routine_run.to_h.merge(store: @retrieval.store, subject: routine_run.subject.to_s, session_id: @writers.session)
        @databases.fetch(:local).transaction { |batch| batch.put(:routine_runs, row) }
        routine_run
      end

      # Keeps the store's own databases out of its versioning; a hook calls
      # this before any read, because a read alone can create the files.
      def ignore_databases = @folder.ignore_databases

      def write_intent(**intent)
        @folder.ignore_databases
        @writers.intents.write(**intent)
      end

      # Prints store/index.json and every file of one intent; returns the paths written.
      def print_intent(intent_id)
        @folder.ignore_databases
        intent = @retrieval.intent(intent_id)
        @writers.sync.printer.print([Prints.index(@retrieval), *Prints.of_intent(@retrieval, intent)])
      end

      # Prints a roadmap's file from its rows; returns the paths written.
      def print_roadmap(slug) = @writers.sync.printer.print([Prints.roadmap(@retrieval, slug)])

      # Opens a ready item's intent, with its spec held in rows. Returns
      # [intent_id, problem, kind]; kind is :failure or :refusal, nil on success.
      def start_roadmap_item(slug, item_id) = Knowledge::Roadmap::ItemStart.new(@writers).call(slug, item_id)

      def print_index = @writers.sync.printer.print([Prints.index(@retrieval)])

      # The paths this call printed, relative to the store folder.
      def printed = @writers.sync.printer.written

      def noter = (@noter ||= Knowledge::Intent::Noter.new(@writers.databases, @writers.retrieval, @writers.folder))

      def preview_sync(options, direction: :up)
        Knowledge::Sync::Preview.new(home_dir, @retrieval.store, options, direction:).call
      end

      # Returns [ok, problem, kind]; kind is :failure or :refusal, nil on success.
      def archive_intent(intent_id)
        @folder.ignore_databases
        @writers.archives.archive(intent_id)
      end

      # The backups of this store: write, preview, list, purge and restore.
      def backups
        store = @retrieval.store
        Knowledge::Backup::StoreBackups.new(local_db, File.join(home_dir, "stores", store), store, session: @writers.session)
      end

      private

      def local_db = @databases.fetch(:local)

      def home_dir = File.dirname(local_db.path)
    end
  end
end
