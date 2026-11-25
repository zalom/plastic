# frozen_string_literal: true

module Plastic
  module Graph
    # Adds back the column that migration 20261125110000 drops from the rulings of the knowledge graph, empty, so a store
    # that went down below it has the layout of the release before it and `plastic update` can drop it again. The merged
    # rulings stay merged. Docs: docs/contributing/MIGRATIONS.md.
    module RulingSupersedesColumn
      # Adds the column and answers that it built no rows.
      def self.call(connection)
        connection.execute(%(ALTER TABLE main."rulings" ADD COLUMN "supersedes" TEXT))
        {}
      end
    end
  end
end
