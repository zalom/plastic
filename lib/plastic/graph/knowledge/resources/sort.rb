# frozen_string_literal: true

require "fileutils"
require_relative "sort_plan"
require_relative "row_moves"

module Plastic
  module Graph
    module Knowledge
      module Resources
        # Sorts the files of a store into the resources layout. The rows move first, then the files, then the
        # files with changed links are written and a sync up reads the result. A file that holds the bytes of its
        # target is deleted with its rows instead of moved. A failure before the sync up puts the files, the rows
        # and the texts back and raises; a sort with nothing to move still runs the sync up when files changed.
        class Sort
          def initialize(folder, graphs, rename: File.method(:rename))
            @folder = folder
            @graphs = graphs
            @rename = rename
          end

          def call
            plan = SortPlan.new(@folder)
            return repair if plan.empty?

            merges, moves = plan.moves.partition { |move| move.onto_same_bytes?(@folder) }
            apply(moves, merges, plan.rewrites)
            settle
            plan.report(moves.size + merges.size)
          end

          private

          def rows = RowMoves.new(@graphs.databases.fetch(:store))

          def apply(moves, merges, rewrites)
            rows.call(moves)
            guarded(moves, rewrites) do
              relocate(moves)
              merge(merges)
              rewrites.each { |rewrite| @folder.write(rewrite.path, rewrite.text) }
            end
          end

          def guarded(moves, rewrites)
            yield
          rescue
            rewrites.each { |rewrite| rewrite.undo(@folder) }
            restore(moves)
            raise
          end

          def relocate(moves)
            moves.each { |move| move.relocate(@folder, @rename) }
          end

          def merge(merges)
            rows.drop(merges)
            merges.each { |move| @folder.delete(move.from) }
          end

          def restore(moves)
            moves.reverse_each { |move| move.reverse.relocate(@folder, File.method(:rename)) if @folder.exist?(move.to) }
            rows.call(moves.map(&:reverse))
          end

          def repair
            return [] unless work.sync_plan(:up, {}).pending.positive?

            settle
            ["sorted: nothing to move; the rows were brought up to date"]
          end

          def work = @graphs.work

          def settle
            work.sync_apply(work.sync_plan(:up, {}))
            @graphs.retrieval.reindex
          end
        end
      end
    end
  end
end
