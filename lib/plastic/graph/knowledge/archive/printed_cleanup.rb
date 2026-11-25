# frozen_string_literal: true

require_relative "../archive"

module Plastic
  module Graph
    module Knowledge
      class Archive
        # Removes printed-file records for a directory that archive deletion removed.
        class PrintedCleanup
          def initialize(databases, retrieval)
            @databases = databases
            @retrieval = retrieval
          end

          def remove(dir)
            keys = printed_keys(dir)
            remove_from(keys) unless keys.empty?
          end

          private

          attr_reader :databases, :retrieval

          def printed_keys(dir)
            retrieval.stored.printed.keys.select { |path| path.start_with?("#{dir}/") }.map { |path| { path: } }
          end

          def remove_from(keys)
            databases.fetch(:store).transaction { |batch| batch.remove_all(:printed, keys) }
          end
        end
      end
    end
  end
end
