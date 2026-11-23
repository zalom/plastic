# frozen_string_literal: true

require "forwardable"
require_relative "log_writer"
require_relative "logged_intents"
require_relative "logged_nodes"
require_relative "logged_records"
require_relative "round_grant"

module Plastic
  module Graph
    module Work
      # The one entry to every write that leaves a work log line. It holds no write of its own: the intent writes are
      # LoggedIntents, the records kept beside an intent LoggedRecords, and the node and edge writes LoggedNodes. A write
      # stores its owning rows and its one work_log row in one transaction, so both land or neither does.
      class LoggedWrites
        extend Forwardable

        attr_reader :grants

        def_delegators :@intents, :write_intent, :close_intent, :abandon_intent, :approve_intent, :park_intent, :archive_intent,
          :unarchive_intent, :revise_intent
        def_delegators :@records, :add_ruling, :add_verdict, :note_intent, :amend_intents, :report_intent, :reporter
        def_delegators :@nodes, :add_node, :claim_node, :record_run, :add_edge, :remove_edge, :drive_intent, :driver_problem, :renew_claims,
          :release_claims, *LoggedNodes::NODE_KINDS.keys

        def initialize(writers)
          log = LogWriter.new(writers)
          @intents = LoggedIntents.new(writers, log)
          @records = LoggedRecords.new(writers, log)
          @nodes = LoggedNodes.new(writers, log)
          @grants = RoundGrant.new(log)
        end
      end
    end
  end
end
