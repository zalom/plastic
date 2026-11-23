# frozen_string_literal: true

require_relative "roadmap_needs"

module Plastic
  module Graph
    # Takes off the store the needs links that migration 20261123120000 wrote, so a store that went down below it holds
    # only the link kinds the release before it reads. A needs link added by hand since stays. The migration kept the keys
    # of the links it wrote in legacy.db; a store with no such record has none to remove. Docs: docs/contributing/MIGRATIONS.md.
    module RoadmapNeedsLinks
      REMOVE = <<~SQL
        DELETE FROM main.links WHERE kind = 'needs'
          AND EXISTS (SELECT 1 FROM legacy."#{RoadmapNeeds::WRITTEN}" w WHERE w.from_ref = links.from_ref AND w.to_ref = links.to_ref)
      SQL

      # Removes the links the migration wrote, drops the record, and answers how many links it removed.
      def self.call(connection)
        return 0 unless recorded?(connection)

        connection.execute(REMOVE)
        connection.changes.tap { connection.execute(%(DROP TABLE legacy."#{RoadmapNeeds::WRITTEN}")) }
      end

      def self.recorded?(connection)
        attached = connection.get_first_value("SELECT 1 FROM pragma_database_list WHERE name = 'legacy'")
        !attached.nil? && !connection.get_first_value("SELECT 1 FROM legacy.sqlite_master WHERE name = ?", RoadmapNeeds::WRITTEN).nil?
      end
    end
  end
end
