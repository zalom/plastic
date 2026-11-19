# frozen_string_literal: true

require "json"
require_relative "earlier_revisions"
require_relative "legacy_table"

module Plastic
  module Graph
    # Trims what migration 20261119000000 kept in legacy.db to what a down needs: the earlier texts of the paths the sync
    # reads. It drops the kept sqlar rows, since each one has a verified copy on disk or in an archive, and the kept
    # revisions that a down rebuilds or that no sync reads. A store then holds the same legacy rows, whichever release
    # ran the drop. Its down removes the version alone. Docs: docs/contributing/MIGRATIONS.md.
    class LegacyTrim
      DROP = "20261119000000"

      # The number of rows it removed from legacy.db.
      Result = Data.define(:removed) do
        def line(slug)
          return if removed.zero?

          "migrate: #{slug} trimmed #{removed} #{(removed == 1) ? "row" : "rows"} from legacy.db that a down rebuilds or that no sync reads"
        end
      end

      DELETE = "DELETE FROM %<table>s WHERE rowid NOT IN (SELECT value FROM json_each(?))"

      # `keep` is the keep of the data step; this step keeps nothing in legacy.db.
      def initialize(connection, _root, selection, keep:)
        @connection = connection
        @selection = selection
        @keep = keep
      end

      def call = Result.new(removed: files + revisions)

      private

      def files
        table = LegacyTable.new(@connection, "sqlar", DROP)
        return 0 unless table.kept?

        table.count.tap { table.drop }
      end

      def revisions
        table = LegacyTable.new(@connection, "document_revisions", DROP)
        return 0 unless table.kept?

        name = %(#{LegacyTable::SCHEMA}."#{table.name}")
        @connection.execute(format(DELETE, table: name), [JSON.generate(EarlierRevisions.new(@connection, @selection).ids(name))])
        @connection.changes
      end
    end
  end
end
