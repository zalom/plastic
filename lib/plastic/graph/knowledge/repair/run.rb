# frozen_string_literal: true

require "fileutils"
require_relative "plan"
require_relative "rebuild/legacy_rows"
require_relative "rebuild/empty_folders"
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
            return plan.missing.lines if plan.empty?

            change(plan)
            remove(plan)
            settle(plan)
            print_logs(plan.amendments)
            plan.report
          end

          private

          # Moves the files, merges those already at their target, rewrites the links and writes the amended lines.
          def change(plan)
            merges, moves = plan.moves.partition { |move| move.onto_same_bytes?(@folder) }
            apply(moves, merges, plan.rewrites, plan.amendments, plan.rebuilds)
          end

          def rows = Resources::RowMoves.new(@graphs.databases.fetch(:store))

          def repair_plan
            retrieval = @graphs.retrieval
            Plan.new(@folder, reports: @reports, ruled: ruled(retrieval), closed: Resources::SortPlan.closed(retrieval), states: MissingFiles.states(retrieval.intents), graphed: retrieval.structure.nodes.to_set(&:intent_id), **@plan)
          end

          # The text of the rulings of an intent, by its id.
          def ruled(retrieval) = ->(id) { retrieval.rulings(id).map(&:text).join("\n") }

          def apply(moves, merges, rewrites, amendments, rebuilds)
            rows.call(moves)
            guarded(moves, rewrites) do
              relocate(moves)
              merge(merges)
              rewrites.each { |rewrite| @folder.write(rewrite.path, rewrite.text) }
              work.amend_intents(amendments)
              work.rebuild_intents(rebuilds)
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
            keep_rows(removals)
            rows.drop(removals)
            removals.each { |removal| gone(removal.path) }
            Rebuild::EmptyFolders.new(@folder).sweep(plan.repaired_dirs)
          end

          # The rows of the files the repair removes go to legacy.db before they leave the knowledge graph.
          def keep_rows(removals) = Rebuild::LegacyRows.new(@folder.root, @graphs.databases.fetch(:store)).keep(removals)

          # Deletes the file, and the folders it leaves empty inside the intent folder.
          def gone(path)
            @folder.delete(path)
            dir = File.dirname(path)
            while dir.count("/") > 1 && Dir.empty?(@folder.path(dir))
              Dir.rmdir(@folder.path(dir))
              dir = File.dirname(dir)
            end
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
