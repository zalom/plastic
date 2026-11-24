# frozen_string_literal: true

module Plastic
  module Graph
    # Puts the column input back on the nodes of the work graph, filled with the first input path of each node, and drops
    # the table node_inputs, so a store that went down below migration 20261123170000 has the layout of the release before
    # it and `plastic update` can move the paths again. A path past the first has no place in the column; the backup a
    # down takes first holds it. Docs: docs/contributing/MIGRATIONS.md.
    module NodeInputsColumn
      FIRST = <<~SQL
        UPDATE work."nodes" SET "input" = (SELECT "path" FROM work."node_inputs" WHERE "node_inputs"."intent_id" = "nodes"."intent_id"
          AND "node_inputs"."node_id" = "nodes"."id" AND "node_inputs"."origin_id" = "nodes"."origin_id" AND "node_inputs"."position" = 1)
      SQL

      # Adds the column, fills it, drops the table and answers that it built no rows.
      def self.call(connection)
        connection.execute(%(ALTER TABLE work."nodes" ADD COLUMN "input" TEXT))
        connection.execute(FIRST)
        connection.execute(%(DROP TABLE work."node_inputs"))
        {}
      end
    end
  end
end
