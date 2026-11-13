# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      class Evidence
        # Reads snapshot rows from the database outside an immediate transaction.
        IntegrityDatabaseSource = Data.define(:database) do
          def rows(sql, **values) = database.rows(sql, **values)
        end

        # Reads snapshot rows through the immediate transaction connection.
        IntegrityTransactionSource = Data.define(:connection) do
          def rows(sql, **values) = connection.read(sql, values)
        end
      end
    end
  end
end
