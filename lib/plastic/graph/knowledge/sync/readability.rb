# frozen_string_literal: true

require_relative "../reader"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # Which changed files a sync up can read into rows. A file is tried with the reader
        # that sync up uses, against the database that owns its rows, in a dry run that
        # takes every statement back.
        class Readability
          def initialize(folder, retrieval, databases)
            @folder = folder
            @retrieval = retrieval
            @databases = databases
          end

          # The reason for each of `paths` that cannot be read, by path.
          def call(paths) = paths.to_h { |path| [path, problem(path)] }.compact

          private

          def problem(path)
            read = reader.read(path)
            @databases.fetch(read.database).dry_run { |batch| read.apply.call(batch) }
            nil
          rescue => error
            error.message
          end

          def reader = (@reader ||= Reader.of_databases(@folder, @retrieval, @databases))
        end
      end
    end
  end
end
