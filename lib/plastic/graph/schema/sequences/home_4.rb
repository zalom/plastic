# frozen_string_literal: true

module Plastic
  module Graph
    # Home migration 4, frozen. The machine database no longer keeps locks: a
    # node's claim in the store says who holds it. Its statement is written out
    # and never calls the live schema. The runner holds the write lock around it.
    module SchemaHome4
      TABLES = { "local" => %w[command_runs sessions settings printed] }.freeze

      TEXT = {
        local: <<~SQL
          DROP TABLE IF EXISTS "locks";
        SQL
      }.freeze

      module_function

      def texts = TEXT.values

      def apply(connection, key) = connection.execute_batch(TEXT.fetch(key))
    end
  end
end
