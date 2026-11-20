# frozen_string_literal: true

require_relative "legacy_table"

module Plastic
  module Graph
    # Gives the free pages of legacy.db back to the disk, in the transaction of the migration. Migration 20261119190000
    # trimmed legacy.db and left the pages it freed in the file, so a store that ran it apart and one that runs both
    # together end the same. A store with no legacy.db gets none. Its down removes the version alone.
    # Docs: docs/contributing/MIGRATIONS.md.
    class LegacyPages
      # The versions that give the free pages of an existing legacy.db back to the disk.
      VERSIONS = %w[20261120090000].freeze
      SCHEMA = LegacyTable::SCHEMA
      ATTACHED = "SELECT count(*) FROM pragma_database_list WHERE name = ?"

      # The number of free pages it gave back.
      Result = Data.define(:pages) do
        def line(slug)
          return if pages.zero?

          "migrate: #{slug} gave #{pages} free #{(pages == 1) ? "page" : "pages"} of legacy.db back to the disk"
        end
      end

      # This step keeps nothing, so it takes no keep.
      def initialize(connection, _root, _selection, **)
        @connection = connection
      end

      def call
        return Result.new(pages: 0) unless @connection.get_first_value(ATTACHED, [SCHEMA]).positive?

        free = @connection.get_first_value("PRAGMA #{SCHEMA}.freelist_count")
        @connection.give_back_free_pages(SCHEMA)
        Result.new(pages: free)
      end
    end
  end
end
