# frozen_string_literal: true

module Plastic
  module Graph
    # Takes the columns of migration 20261123090000 off the runs of the work graph, so a store that went down below it has
    # the layout of the release before it and `plastic update` can add them again. The values they held are in the backup
    # a down takes first. Docs: docs/contributing/MIGRATIONS.md.
    module RunUsageColumns
      NAMES = %w[harness worker_session usage_note model input_tokens output_tokens cache_read_tokens cache_write_tokens cost_usd].freeze

      # Drops the columns and answers that it built no rows.
      def self.call(connection)
        NAMES.each { |name| connection.execute(%(ALTER TABLE work."runs" DROP COLUMN "#{name}")) }
        {}
      end
    end
  end
end
