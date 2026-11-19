# frozen_string_literal: true

require "json"
require_relative "../sql"

module Plastic
  module Graph
    # Drops the rows of every report that the setting reports.mandatory does not name: documents, document_heads,
    # printed and the search rows. The files stay on disk, so a later plastic intent report brings a row back. A report
    # of an earlier intent predates the owner messages, so none of them counts as recorded. It keeps nothing in
    # legacy.db, since a sync up reads a recorded or mandatory report back; a down removes its version alone.
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

      # `keep` is the keep of the data step; this step keeps nothing in legacy.db.
      def initialize(connection, _root, selection, keep:)
        @connection = connection
        @reports = selection.reports
        @keep = keep
      end

      def call
        rows = dropped
        values = { rows: JSON.generate(rows), printed: JSON.generate(printed) }
        STEPS.each { |sql| @connection.execute(sql, SQL.params(sql, values)) }
        Result.new(removed: rows.size)
      end

      private

      # The intent and path of each report row that is not mandatory.
      def dropped = @connection.read(REPORTS).map { |row| row.values_at("intent_id", "path") }.reject { |_intent_id, path| mandatory?(path) }

      # The printed path of each report that is not mandatory; a printed path starts with store/ and the intent folder.
      def printed = @connection.read(PRINTED).map { |row| row.fetch("path") }.reject { |path| mandatory?(path.split("/", 3).last) }

      def mandatory?(rel) = @reports.mandatory?(rel)
    end
  end
end
