# frozen_string_literal: true

module Plastic
  module Graph
    # Takes the column of migration 20261124173000 off the drivers of the work graph, so a store that went down below it
    # has the layout of the release before it and `plastic update` can add it again. The values it held are in the
    # backup a down takes first. Docs: docs/contributing/MIGRATIONS.md.
    module DriverModeColumn
      # Drops the column and answers that it built no rows.
      def self.call(connection)
        connection.execute(%(ALTER TABLE work."drivers" DROP COLUMN "mode"))
        {}
      end
    end
  end
end
