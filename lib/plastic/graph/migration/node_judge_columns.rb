# frozen_string_literal: true

module Plastic
  module Graph
    # Puts the columns of migration 20261123100000 back on the nodes of the work graph, empty, so a store that went down
    # below it has the layout of the release before it and `plastic update` can drop them again. No store held a value in
    # them; the backup a down takes first holds any a store did. Docs: docs/contributing/MIGRATIONS.md.
    module NodeJudgeColumns
      NAMES = %w[judge verdict].freeze

      # Adds the columns and answers that it built no rows.
      def self.call(connection)
        NAMES.each { |name| connection.execute(%(ALTER TABLE work."nodes" ADD COLUMN "#{name}" TEXT)) }
        {}
      end
    end
  end
end
