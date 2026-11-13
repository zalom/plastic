# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "import_metadata"
require_relative "import_rollback"
require_relative "import_cleanup"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # The complete first sync of one legacy store, with rollback and preserved originals.
        class StoreImport
          def initialize(reader, folder, retrieval, databases, rollback: ImportRollback)
            home = File.dirname(databases.fetch(:local).path)
            @rollback = rollback.new(folder.root)
            @reader = reader
            @metadata = ImportMetadata.new(folder, retrieval, home)
            @cleanup = ImportCleanup.new(folder, retrieval, home)
          end

          def call
            lines, counts = imported
            @cleanup.call(counts)
            [*lines, "imported metadata: #{Schema.phrase(counts)}"]
          end

          private

          def imported = failing { @rollback.call { @metadata.call { @reader.read_rows } } }

          def failing
            yield
          rescue Check::Failed
            raise
          rescue => error
            raise Invalid, "#{@metadata.store}: the import failed: #{error.message}"
          end
        end
      end
    end
  end
end
