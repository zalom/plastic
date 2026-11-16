# frozen_string_literal: true

module Plastic
  module Graph
    # Home migration 2, frozen. The machine database keeps command runs
    # under a name that says what they are, and the backups table goes: the
    # backup folders on disk are the record of backups. Its statements are
    # written out and never call the live schema. The runner holds the write
    # lock around it.
    module SchemaHome2
      TABLES = { "local" => %w[command_runs sessions locks] }.freeze

      TEXT = {
        local: <<~SQL
          ALTER TABLE "routine_runs" RENAME TO "command_runs";
          DROP TABLE IF EXISTS "backups";
        SQL
      }.freeze

      module_function

      def texts = TEXT.values

      def apply(connection, key) = connection.execute_batch(TEXT.fetch(key))
    end
  end
end
