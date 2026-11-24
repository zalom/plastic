# frozen_string_literal: true

module Plastic
  module Graph
    # Takes the columns of migration 20261124210000 off the work log of the work graph, so a store that went down below it
    # has the layout of the release before it and `plastic update` can add them again. The values they held are in the
    # backup a down takes first. Docs: docs/contributing/MIGRATIONS.md.
    module WorkLogTextColumns
      # Drops the columns and answers that it built no rows.
      def self.call(connection)
        connection.execute(%(ALTER TABLE work."work_log" DROP COLUMN "old_text"))
        connection.execute(%(ALTER TABLE work."work_log" DROP COLUMN "new_text"))
        {}
      end
    end
  end
end
