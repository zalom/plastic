# frozen_string_literal: true

require "forwardable"
require_relative "backup/store_backups"
require_relative "printer"
require_relative "knowledge/prints"
require_relative "knowledge/sync/preview"
require_relative "writers"
require_relative "work/logged_writes"
require_relative "work/session_intent"
require_relative "knowledge/intent/noter"

module Plastic
  module Graph
    # The write side of the graphs: command runs and sessions at the
    # home, and the rows and printed files of one store. Every write keeps
    # the store's databases out of its versioning. `session` names the
    # harness session this call runs as, nil when the harness sets none.
    class GraphWriter
      extend Forwardable

      def_delegators "@writers.sessions", :open_session, :stamp_turn, :end_session, :write_note
      def_delegator "@writers.intents", :activate, :activate_intent
      def_delegator "@writers.intents", :open_problem, :open_intent_problem
      def_delegator "@writers.intents", :problem, :intent_problem
      def_delegator "@writers.intents", :ref_line
      def_delegator "@writers.revisions", :change, :revision
      def_delegator "Plastic::Graph::Knowledge::Intent::Noter", :problem, :note_problem
      def_delegator "@logged.reporter", :problem, :report_problem
      def_delegator "@logged.reporter", :state, :report_state
      def_delegator "@logged.reporter", :restate, :restate_report
      def_delegators :@logged, :close_intent, :abandon_intent, :park_intent, :approve_intent, :add_ruling, :add_verdict,
        :revise_intent, :note_intent, :report_intent, :amend_intents, :add_node, :claim_node, :record_run, :done_node, :fail_node, :ask_node, :impede_node, :resolve_node, :release_node,
        :remove_node, :add_edge, :remove_edge
      def_delegators "@writers.nodes", :renew_claims
      def_delegators "@writers.verdicts", :rounds_left?
      def_delegator "@logged.grants", :write, :grant_round
      def_delegators "@writers.links", :add_link, :remove_link
      def_delegator "@writers.links", :target_problem, :link_target_problem
      def_delegator "@writers.links", :refusal, :link_refusal
      def_delegator "@writers.sync", :plan, :sync_plan
      def_delegator "@writers.sync", :apply, :sync_apply
      def_delegator "@writers.sync", :hand_edited
      def_delegator "@writers.sync.printer", :written, :printed
      def_delegator :@folder, :ignore_databases

      def initialize(databases, folder:, retrieval:, session: nil, **seams)
        @folder = folder
        @retrieval = retrieval
        @writers = Writers.new(databases, retrieval, folder, session, seams.fetch(:clock, Time))
        @logged = Work::LoggedWrites.new(@writers)
      end

      # A command run is call memory, kept off the report.
      def save_command_run(command_run)
        row = command_run.to_h.merge(store: @retrieval.store, subject: command_run.subject.to_s, session_id: @writers.session)
        @writers.databases.fetch(:local).transaction { |batch| batch.put(:command_runs, row) }
        command_run
      end

      def write_intent(**intent)
        @folder.ignore_databases
        @logged.write_intent(**intent)
      end

      # Prints store/index.json and every file of one intent; returns the paths written.
      def print_intent(intent_id)
        @folder.ignore_databases
        intent = @retrieval.intent(intent_id)
        @writers.sync.printer.print([Prints.index(@retrieval), *Prints.of_intent(@retrieval, intent)])
      end

      # The snapshot restores exact bytes; the work.log it holds lacks the line this call just wrote, so that one file is printed again.
      # Returns [ok, problem, kind]; kind is :failure, nil on success.
      def unarchive_intent(intent_id)
        @logged.unarchive_intent(intent_id).tap { |ok,| @writers.sync.printer.reprint(Prints.log_of(@retrieval, intent_id)) if ok }
      end

      def print_index = @writers.sync.printer.print([Prints.index(@retrieval)])

      def preview_sync(options, direction: :up)
        Knowledge::Sync::Preview.new(home_dir, @retrieval.store, options, direction:).preview(@folder.sync)
      end

      # Returns [ok, problem, kind]; kind is :failure or :refusal, nil on success.
      def archive_intent(intent_id)
        @folder.ignore_databases
        @logged.archive_intent(intent_id)
      end

      # The backups of this store: write, preview, list, purge and restore.
      def backups
        store = @retrieval.store
        Backup::StoreBackups.new(local_db, File.join(home_dir, "stores", store), @retrieval, session: @writers.session, clock: @writers.clock)
      end

      private

      def local_db = @writers.databases.fetch(:local)

      def home_dir = File.dirname(local_db.path)
    end
  end
end
