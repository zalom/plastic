# frozen_string_literal: true

require "json"
require_relative "../sql"
require_relative "../knowledge/sync_selection"

module Plastic
  module Graph
    # Drops the rows of every report that is neither recorded nor mandatory, the rule the sync reads by: documents,
    # document_heads, printed and the search rows. The files stay on disk, so a later plastic intent report brings a row
    # back. It keeps nothing in legacy.db, since a sync up reads a recorded or mandatory report back; a down removes its
    # version alone.
    class ReportRows
      # The number of reports whose rows it dropped.
      Result = Data.define(:removed) do
        def line(slug)
          return if removed.zero?

          "migrate: #{slug} dropped the rows of #{removed} reports that are neither recorded nor mandatory; the files stay on disk"
        end
      end

      REPORTS = "SELECT DISTINCT intent_id, path FROM main.documents WHERE path GLOB 'resources/output/reports/*'"
      PRINTED = "SELECT path FROM main.printed WHERE path GLOB 'store/*/resources/output/reports/*'"
      PAIRS = "SELECT json_extract(value, '$[0]'), json_extract(value, '$[1]') FROM json_each(:rows)"
      STEPS = [
        "DELETE FROM main.documents WHERE (intent_id, path) IN (#{PAIRS})",
        "DELETE FROM main.document_heads WHERE (intent_id, path) IN (#{PAIRS})",
        "DELETE FROM main.printed WHERE path IN (SELECT value FROM json_each(:printed))",
        "DELETE FROM retrieval.document_passages WHERE (intent_id, path) IN (#{PAIRS})",
        "DELETE FROM retrieval.document_fts WHERE (intent_id, path) IN (#{PAIRS})"
      ].freeze

      # The recorded reports of the work log, read through the migration's connection.
      WorkLog = Data.define(:connection) do
        def rows(sql) = connection.read(sql)
      end

      # `keep` is the keep of the data step; this step keeps nothing in legacy.db.
      def initialize(connection, _root, selection, keep:)
        @connection = connection
        @reports = selection.reports.recorded_from(WorkLog.new(connection))
        @keep = keep
      end

      def call
        rows = dropped
        values = { rows: JSON.generate(rows), printed: JSON.generate(printed) }
        STEPS.each { |sql| @connection.execute(sql, SQL.params(sql, values)) }
        Result.new(removed: rows.size)
      end

      private

      # The intent and path of each report row that is neither recorded nor mandatory.
      def dropped = (@dropped ||= @connection.read(REPORTS).map { |row| row.values_at("intent_id", "path") }.reject { |intent_id, path| @reports.listed?(intent_id, path) })

      # The printed path of each dropped report; a printed path is store/, the intent folder, then the path inside it.
      def printed
        dropped_pairs = dropped.to_set
        @connection.read(PRINTED).map { |row| row.fetch("path") }.select { |path| dropped_pairs.include?(pair_of(path)) }
      end

      def pair_of(printed) = [Knowledge::SyncSelection.intent_of(printed), printed.split("/", 3).last]
    end
  end
end
