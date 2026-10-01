# frozen_string_literal: true

require "forwardable"
require_relative "intent_writer"
require_relative "node_writer"
require_relative "edge_writer"
require_relative "ruling_writer"
require_relative "link_writer"
require_relative "roadmap_writer"
require_relative "roadmap_state"
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
      def_delegators :nodes, :add_node, :remove_node, :claim_node, :release_node, :done_node, :fail_node,
        :park_node, :answer_node
      def_delegators :edges, :add_edge, :remove_edge
      def_delegators :rulings, :add_ruling
      def_delegators :links, :add_link, :remove_link
      def_delegators :roadmaps, :write_batch, :add_item, :drop_item, :remove_roadmap_edge, :add_log

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

      def link_target_problem(id, target) = links.target_problem(id, target)

      def link_refusal(id, target, kind) = links.refusal(id, target, kind)

      # Prints store/index.json and every file of one intent; returns the paths written.
      def print_intent(intent_id)
        @folder.ignore_databases
        intent = @retrieval.intent(intent_id)
        sync.printer.print([Prints.index(@retrieval), *Prints.of_intent(@retrieval, intent)])
      end

      # Prints a roadmap's file from its rows; returns the paths written.
      def print_roadmap(slug)
        sync.printer.print([Prints.roadmap(@retrieval, slug)])
      end

      # Opens a ready item's intent, with its spec held in rows. Returns
      # [intent_id, problem, kind]; kind is :failure or :refusal, nil on success.
      def start_roadmap_item(slug, item_id)
        item = @retrieval.roadmap_items(slug).find { |row| row.item == item_id }
        return [nil, "no item #{item_id} on roadmap #{slug}", :failure] unless item

        problem = start_problem(item)
        return [nil, problem, :refusal] if problem

        open_roadmap_item(slug, item)
      end

      def sync_plan(direction, options) = sync.plan(direction, options)

      def sync_apply(plan) = sync.apply(plan)

      private

      def sessions = (@sessions ||= SessionWriter.new(@databases.fetch(:home), store: @retrieval.store))

      def intents = (@intents ||= IntentWriter.new(@databases, @retrieval, @folder, session: @session))

      def nodes = (@nodes ||= NodeWriter.new(@databases, @retrieval))

      def edges = (@edges ||= EdgeWriter.new(@databases, @retrieval))

      def rulings = (@rulings ||= RulingWriter.new(@databases, @retrieval, session: @session))

      def links = (@links ||= LinkWriter.new(@databases, @retrieval))

      def roadmaps = (@roadmaps ||= RoadmapWriter.new(@databases, @retrieval, session: @session))

      def sync = (@sync ||= Sync.new(folder: @folder, retrieval: @retrieval, databases: @databases))

      def start_problem(item)
        return "item #{item.item} already has an intent" if item.intent_id

        state = RoadmapState.of(item, @retrieval)
        "item #{item.item} is #{state}, not ready" unless state == "ready"
      end

      def open_roadmap_item(slug, item)
        intent = intents.write(title: item.title)
        write_spec_document(intent.intent_id, batch_of(slug, item), item)
        roadmaps.start_item(slug, item.item, intent.intent_id)
        links.add_link(from_ref: intent.intent_id, to_ref: "roadmap:#{slug}", kind: "source")
        [intent.intent_id, nil, nil]
      end

      def batch_of(slug, item) = @retrieval.batches(slug).find { |row| row.position == item.batch }

      def write_spec_document(intent_id, batch, item)
        row = { intent_id:, path: "spec.md", body: spec_body(batch, item), updated_at: Plastic.now }
        @databases.fetch(:knowledge).transaction { |transaction| transaction.put(:documents, row, statement: :insert) }
      end

      def spec_body(batch, item)
        goal = [batch&.goal, item.goal].compact
        done = (batch&.done_lines || []) + item.done_lines
        lines = ["## Goal", "", *goal, "", "## Done criteria", "", *done.map { |line| "- [ ] #{line}" }, ""]
        lines.join("\n")
      end
    end
  end
end
