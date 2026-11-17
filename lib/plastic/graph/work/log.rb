# frozen_string_literal: true

require "digest"
require "securerandom"
require_relative "log_line"

module Plastic
  module Graph
    module Work
      # The outbox of an intent's work log. A write stores its owning rows and one pending row in
      # one transaction; a drain turns each pending row into one work_log line, keyed by its
      # write id, so a drain that runs twice, or after a death, adds each line once.
      class Log
        PENDING_COLUMNS = %i[write_id intent_id at phase node session_id kind path sha256 text origin_id].freeze
        STAGE_SQL = "INSERT INTO work_log_pending(#{PENDING_COLUMNS.join(", ")}) VALUES (#{PENDING_COLUMNS.map { |column| ":#{column}" }.join(", ")})"
        OWED_SQL = "SELECT * FROM work_log_pending WHERE intent_id = :intent_id ORDER BY rowid"
        TOP_SQL = "SELECT COALESCE(MAX(position), 0) AS top FROM work_log WHERE intent_id = :intent_id"
        WRITTEN_SQL = "SELECT 1 FROM work_log WHERE origin_id = :origin_id AND write_id = :write_id"
        OWING_SQL = "SELECT DISTINCT intent_id FROM work_log_pending ORDER BY intent_id"
        FORGET_SQL = "DELETE FROM work_log_pending WHERE write_id = :write_id"

        def initialize(databases, retrieval, session:)
          @databases = databases
          @retrieval = retrieval
          @session = session
        end

        # Runs the block, which writes the owning rows and stages their lines, as one commit.
        def atomically(&) = work.atomically { @databases.fetch(:knowledge).atomically(&) }

        # `parts` may name the node, the path and the body of the document the line hashes.
        def stage(intent_id, kind, text, **parts)
          row = { write_id: SecureRandom.uuid, intent_id:, at: Plastic.now, phase: "", node: "", session_id: @session, kind:, path: "", text:,
                  origin_id: @retrieval.origin_id, **parts.slice(:node, :path), sha256: hash_of(parts[:body]) }
          work.transaction { |batch| batch.add(STAGE_SQL, **row) }
        end

        # Turns the pending rows of one intent into lines; returns how many lines it added.
        def drain(intent_id)
          added = 0
          work.immediate_transaction do |batch, connection|
            owed = connection.read(OWED_SQL, { intent_id: })
            rows = line_rows(connection, owed)
            batch.put_all(:work_log, rows)
            added = rows.size
            owed.each { |row| batch.add(FORGET_SQL, write_id: row.fetch("write_id")) }
          end
          added
        end

        # Drains every intent that owes lines; returns the lines added, by intent id.
        def drain_all
          work.rows(OWING_SQL).map { |row| row.fetch("intent_id") }.to_h { |intent_id| [intent_id, drain(intent_id)] }
        end

        private

        def work = @databases.fetch(:work)

        def hash_of(body) = body ? Digest::SHA256.hexdigest(body) : ""

        def line_rows(connection, owed)
          fresh = owed.reject { |row| written?(connection, row) }
          top = fresh.empty? ? 0 : connection.read(TOP_SQL, { intent_id: fresh.first.fetch("intent_id") }).first.fetch("top")
          fresh.each_with_index.map { |row, index| row.transform_keys(&:to_sym).merge(position: top + index + 1) }
        end

        def written?(connection, row) = connection.read(WRITTEN_SQL, { origin_id: row.fetch("origin_id"), write_id: row.fetch("write_id") }).any?
      end
    end
  end
end
