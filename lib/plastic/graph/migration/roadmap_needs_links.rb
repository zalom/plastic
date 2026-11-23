# frozen_string_literal: true

module Plastic
  module Graph
    # Takes the needs links off the store, so a store that went down below migration 20261123120000 holds only the link
    # kinds the release before it reads. The links are in the backup a down takes first. Docs: docs/contributing/MIGRATIONS.md.
    module RoadmapNeedsLinks
      # Removes every needs link and answers how many.
      def self.call(connection)
        connection.execute("DELETE FROM main.links WHERE kind = 'needs'")
        { "links" => connection.changes }
      end
    end
  end
end
