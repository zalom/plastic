# frozen_string_literal: true

module Plastic
  module Graph
    # Writes every stored time of a store that carries an offset in UTC, the form Plastic.timestamp writes, and keeps
    # each old text in legacy.db so a down can put it back. A date, a time already in UTC and a blank stay as they are.
    # Docs: docs/contributing/MIGRATIONS.md.
    class UtcTimes
      # The time columns of the store, as schema.table.column.
      COLUMNS = %w[
        main.intents.opened_at main.intents.closed_at main.intents.updated_at main.completions.at main.approvals.at
        main.verdicts.at main.printed.at main.archives.at main.archives.restored_at main.documents.updated_at
        main.legacy_intents_data.updated_at main.document_heads.updated_at main.retrieval_contexts.updated_at
        main.retrieval_discoveries.updated_at main.rulings.at main.links.at
        work.nodes.updated_at work.nodes.claimed_at work.nodes.seen_at work.nodes.answered_at work.runs.started_at
        work.runs.ended_at work.work_log.at work.roadmaps.opened_at work.roadmaps.updated_at work.batches.updated_at
        work.roadmap_items.updated_at work.roadmap_log.at
      ].freeze

      # One time column: the values it selects, the UTC text it makes of each, and the statement that writes it.
      Column = Data.define(:schema, :table, :name) do
        def where = %("#{name}" GLOB '????-??-??T??:??:??[+-]??:??')

        def change = %(strftime('%Y-%m-%dT%H:%M:%SZ', "#{name}"))

        def update = %(UPDATE #{schema}."#{table}" SET "#{name}" = #{change} WHERE #{where})
      end

      # The number of times it wrote in UTC.
      Result = Data.define(:changed) do
        def line(slug)
          return if changed.zero?

          "migrate: #{slug} wrote #{changed} #{(changed == 1) ? "time" : "times"} in UTC"
        end
      end

      def self.columns = COLUMNS.map { |path| Column.new(*path.split(".")) }

      # `keep` is the keep of the data step, which keeps the old text of each value it rewrites.
      def initialize(connection, _root, _selection, keep:)
        @connection = connection
        @keep = keep
      end

      def call = Result.new(changed: self.class.columns.sum { |column| rewrite(column) })

      private

      def rewrite(column)
        @keep.values(column)
        @connection.execute(column.update)
        @connection.changes
      end
    end
  end
end
