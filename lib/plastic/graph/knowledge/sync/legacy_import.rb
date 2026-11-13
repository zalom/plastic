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
            rows = LegacyRows.new(sync, folder, retrieval, databases)
            @import = Legacy::StoreImport.new(rows, folder, retrieval, databases, rollback:)
          end

          def call = @import.call
        end
      end
    end
  end
end
