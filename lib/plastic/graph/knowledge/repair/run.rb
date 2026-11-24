# frozen_string_literal: true

require "fileutils"
require_relative "plan"
require_relative "../reports"
require_relative "../../knowledge/resources/row_moves"

module Plastic
  module Graph
    module Knowledge
      module Repair
        # Applies the repair plan of the intent folders of one store folder. The plan is read whole first, so a revisions.md
        # it cannot read refuses the repair before anything changes. Then the rows move, the files move, the files with
        # changed links are written and the `amended` lines go in one transaction; a failure there puts the files, the rows
        # and the texts back and raises. A file that holds the bytes of its target is deleted with its rows instead of
        # moved. Only then are the old files removed with their rows, a sync up reads the result, the search rows of the
        # intents that changed are built again, and the work.log of each amended intent is printed again. A repair with
        # nothing to change writes nothing. The options of the plan are those of Plan: the `zone` of the revision times, and
        # the scope, `dirs`, every folder when nil, never one of `held`.
        class Run
          def initialize(folder, graphs, reports: Reports.none, rename: File.method(:rename), **plan)
            @folder = folder
            @graphs = graphs
            @reports = reports.recorded_from(graphs.databases.fetch(:store))
            @rename = rename
            @plan = plan
          end

          def call
            plan = repair_plan
            return [] if plan.empty?

            amendments = plan.amendments
            merges, moves = plan.moves.partition { |move| move.onto_same_bytes?(@folder) }
            apply(moves, merges, plan.rewrites, amendments)
            remove(plan)
            settle(plan)
            print_logs(amendments)
            plan.report
          end

          private

          def rows = Resources::RowMoves.new(@graphs.databases.fetch(:store))

          def repair_plan
            closed = Resources::SortPlan.closed(@graphs.retrieval)
            Plan.new(@folder, reports: @reports, closed:, **@plan)
          end

          def apply(moves, merges, rewrites, amendments)
            rows.call(moves)
            guarded(moves, rewrites) do
              relocate(moves)
              merge(merges)
              rewrites.each { |rewrite| @folder.write(rewrite.path, rewrite.text) }
              work.amend_intents(amendments)
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

          # The old files and each revisions.md, whose entries are amended lines by now, go with their rows.
          def remove(plan)
            removals = [*plan.removals, *plan.revision_files.map { |path| Removal.new(path) }]
            rows.drop(removals)
            removals.each { |removal| @folder.delete(removal.path) }
          end

          def work = @graphs.work

          def settle(plan)
            work.sync_apply(work.sync_plan(:up, {}))
            paths = [*plan.moves.map(&:from), *plan.removals.map(&:path), *plan.revision_files]
            @graphs.retrieval.reindex(paths.map { |path| SyncSelection.intent_of(path) }.uniq)
          end

          def print_logs(amendments) = amendments.map(&:intent_id).uniq.each { |intent_id| work.print_intent(intent_id) }
        end
      end
    end
  end
end
