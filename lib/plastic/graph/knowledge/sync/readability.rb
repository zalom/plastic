# frozen_string_literal: true

require_relative "../reader"
require_relative "../../database/batch"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # Which changed files a sync up can read into rows. A file is tried with the reader
        # that sync up uses, against a batch that nothing commits.
        class Readability
          # The origin a batch stamps its rows with.
          Origin = Data.define(:id)

          def initialize(folder, retrieval)
            @folder = folder
            @retrieval = retrieval
          end

          # The reason for each of `paths` that cannot be read, by path.
          def call(paths) = paths.to_h { |path| [path, problem(path)] }.compact

          private

          def problem(path)
            reader.read(path).apply.call(Database::Batch.new(origin: Origin.new(@retrieval.origin_id)))
            nil
          rescue => error
            error.message
          end

          def reader = (@reader ||= Reader.of(@folder, @retrieval))
        end
      end
    end
  end
end
