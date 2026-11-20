# frozen_string_literal: true

require "fileutils"
require_relative "sort_plan"
require_relative "row_moves"

module Plastic
  module Graph
    module Knowledge
      module Resources
        # Sorts the files of a store into the resources layout. The rows move first, then the files, then the
        # files with changed links are written, then the `amended` lines in one transaction, and a sync up reads the
        # result. A file that holds the bytes of its target is deleted with its rows instead of moved. A failure before
        # the sync up puts the files, the rows and the texts back and raises; a sort with nothing to move still runs the sync up when files changed. The
        # mandatory names of `reports` and the reports the store recorded stay in resources/output/reports/; every other
        # report moves to resources/tmp/ and is named. Each link rewritten in a core file of a done or abandoned intent
        # leaves an `amended` line on that intent's work log, and the work.log file of that intent is printed again. The
        # search rows of the intents whose files moved are built again in one pass.
        class Sort
          def initialize(folder, graphs, reports: Reports.none, rename: File.method(:rename))
            @folder = folder
            @graphs = graphs
            @reports = reports.recorded_from(graphs.databases.fetch(:store))
            @rename = rename
          end

          def call
            plan = sort_plan
            return repair if plan.empty?

            merges, moves = plan.moves.partition { |move| move.onto_same_bytes?(@folder) }
            apply(moves, merges, plan)
            settle(moves + merges)
            print_logs(plan.amendments)
            plan.report(moves.size + merges.size)
          end

          private

          def rows = RowMoves.new(@graphs.databases.fetch(:store))

          def sort_plan = SortPlan.new(@folder, reports: @reports, closed: SortPlan.closed(@graphs.retrieval))

          def apply(moves, merges, plan)
            rewrites = plan.rewrites
            rows.call(moves)
            guarded(moves, rewrites) do
              relocate(moves)
              merge(merges)
              rewrites.each { |rewrite| @folder.write(rewrite.path, rewrite.text) }
              work.amend_intents(plan.amendments)
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

          def settle(moves = [])
            work.sync_apply(work.sync_plan(:up, {}))
            @graphs.retrieval.reindex(moves.filter_map { |move| SyncSelection.intent_of(move.from) }.uniq)
          end

          def print_logs(amendments) = amendments.map(&:intent_id).uniq.each { |intent_id| work.print_intent(intent_id) }
        end
      end
    end
  end
end
