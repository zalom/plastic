# frozen_string_literal: true

require_relative "legacy_rows"
require_relative "../legacy/store_import"

module Plastic
  module Graph
    module Knowledge
      class Graph::Knowledge::Sync
        # The full first sync delegates preservation and metadata to Graph::Knowledge::Legacy::StoreImport.
        class LegacyImport
          def initialize(sync, folder, retrieval, databases, rollback: Legacy::ImportRollback)
            @rows = LegacyRows.new(sync, folder, retrieval, databases)
            @import = Legacy::StoreImport.new(@rows, folder, retrieval, databases, rollback:)
          end

          # The links of the old store are written after its files are read, so the index is printed once more to list them.
          def call = @import.call.tap { @rows.print_index }
        end
      end
    end
  end
end
