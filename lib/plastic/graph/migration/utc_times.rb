# frozen_string_literal: true

module Plastic
  module Graph
    # Writes every stored time of a store that carries an offset in UTC, the form Plastic.timestamp writes, and keeps
    # each old text in legacy.db so a down can put it back. A date, a time already in UTC and a blank stay as they are. A
    # time with an offset that names no real moment, such as hour 25, stays as it is too, and the line names it.
    # Docs: docs/contributing/MIGRATIONS.md.
    class UtcTimes
      VERSION = "20261121090000"
      # The time columns of the store, as schema.table.column.
      COLUMNS = %w[
        main.intents.opened_at main.intents.closed_at main.intents.updated_at main.completions.at main.approvals.at
        main.verdicts.at main.printed.at main.archives.at main.archives.restored_at main.documents.updated_at
        main.legacy_intents_data.updated_at main.document_heads.updated_at main.retrieval_contexts.updated_at
        main.retrieval_discoveries.updated_at main.rulings.at main.links.at
        work.nodes.updated_at work.nodes.claimed_at work.nodes.seen_at work.nodes.answered_at work.runs.started_at
        work.runs.ended_at work.work_log.at
      ].freeze
      # The time columns of plastic.db, which its own SQL migration of this version writes in UTC.
      HOME_COLUMNS = %w[
        main.command_runs.started_at main.command_runs.updated_at main.sessions.started_at main.sessions.last_turn_at
        main.sessions.ended_at main.printed.at main.chat_messages.at main.store_migrations.at
      ].freeze

      # One time column: the values it selects, the UTC text it makes of each, the statement that writes it, and the
      # query that names each time with an offset it cannot read.
      Column = Data.define(:schema, :table, :name) do
        def shape = %("#{name}" GLOB '????-??-??T??:??:??[+-]??:??')

        def change = %(strftime('%Y-%m-%dT%H:%M:%SZ', "#{name}"))

        def where = "#{shape} AND #{change} IS NOT NULL"

        def update = %(UPDATE #{schema}."#{table}" SET "#{name}" = #{change} WHERE #{where})

        def unreadable = %(SELECT "#{name}" AS value FROM #{schema}."#{table}" WHERE #{shape} AND #{change} IS NULL ORDER BY 1)

        def label(value) = "#{schema}.#{table}.#{name} #{value}"
      end

      # The number of times it wrote in UTC, and each time it could not read, as its column and its text.
      Result = Data.define(:changed, :unreadable) do
        def initialize(changed:, unreadable: []) = super

        def line(slug)
          parts = [(wrote if changed.positive?), (left if unreadable.any?)].compact
          "migrate: #{slug} #{parts.join(" and ")}" unless parts.empty?
        end

        private

        def wrote = "wrote #{changed} #{(changed == 1) ? "time" : "times"} in UTC"

        def left = "left #{unreadable.size} unreadable #{(unreadable.size == 1) ? "time" : "times"} unchanged: #{unreadable.join(", ")}"
      end

      def self.columns(paths = COLUMNS) = paths.map { |path| Column.new(*path.split(".")) }

      # Each time with an offset that the `paths` columns hold and that names no real moment.
      def self.unreadable(connection, paths) = columns(paths).flat_map { |column| connection.execute(column.unreadable).map { |row| column.label(row.fetch("value")) } }

      # `keep` is the keep of the data step, which keeps the old text of each value it rewrites.
      def initialize(connection, _root, _selection, keep:)
        @connection = connection
        @keep = keep
      end

      def call = Result.new(changed: self.class.columns.sum { |column| rewrite(column) }, unreadable: self.class.unreadable(@connection, COLUMNS))

      private

      def rewrite(column)
        @keep.values(column)
        @connection.execute(column.update)
        @connection.changes
      end
    end
  end
end
