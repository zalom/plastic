# frozen_string_literal: true

require "fileutils"
require_relative "sort_plan"
require_relative "row_moves"

module Plastic
  module Graph
    module Knowledge
      module Resources
        # Sorts the files of a store into the resources layout. The rows move first, then the files, then the
        # files with changed links are written and a sync up reads the result. A file that cannot move puts the
        # files and the rows back and raises.
        class Sort
          def initialize(folder, graphs, rename: File.method(:rename))
            @folder = folder
            @graphs = graphs
            @rename = rename
          end

          def call
            plan = SortPlan.new(@folder)
            return [] if plan.empty?

            moves = plan.moves
            rewrites = plan.rewrites
            rows.call(moves)
            relocate(moves)
            rewrites.each { |rewrite| @folder.write(rewrite.path, rewrite.text) }
            settle
            ["sorted: #{moves.size} files moved"]
          end

          private

          def rows = RowMoves.new(@graphs.databases.fetch(:store))

          def relocate(moves)
            done = []
            moves.each do |move|
              FileUtils.mkdir_p(File.dirname(@folder.path(move.to)))
              @rename.call(@folder.path(move.from), @folder.path(move.to))
              done << move
            end
          rescue StandardError
            restore(done, moves)
            raise
          end

          def restore(done, moves)
            done.reverse_each { |move| File.rename(@folder.path(move.to), @folder.path(move.from)) }
            rows.call(moves, back: true)
          end

          def settle
            work = @graphs.work
            work.sync_apply(work.sync_plan(:up, {}))
            @graphs.retrieval.reindex
          end
        end
      end
    end
  end
end
