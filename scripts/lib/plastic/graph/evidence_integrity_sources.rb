# frozen_string_literal: true

module Plastic
  module Graph
    # Reads snapshot rows from the database outside an immediate transaction.
    EvidenceIntegrityDatabaseSource = Data.define(:database) do
      def rows(sql) = database.rows(sql)
    end

    # Reads snapshot rows through the immediate transaction connection.
    EvidenceIntegrityTransactionSource = Data.define(:connection) do
      def rows(sql) = connection.sets(sql).first || []
    end
  end
end
