# frozen_string_literal: true

require_relative "../command"
require_relative "../../store_sync"
require_relative "../../work_graph"

module Plastic
  class CLI
    module Commands
      class Sync < Command
        USAGE_LINE = "plastic sync [--dry-run] [--json]"

        def call
          home = scope.plastic_home
          plan = File.exist?(SearchIndex.path(home)) ? StoreSync.plan(home) : [["build", SearchIndex::NAME]]
          refuse(home, plan.filter_map { |action, path| path if action == "conflict" })
          plan.group_by(&:first).each { |action, pairs| @output.row(action, pairs.map(&:last)) }
          @output.row("result", "nothing to do") if plan.empty?
          apply(home, plan) unless options[:dry_run]
          @output.next_step("plastic search TERMS", because: "a changed file is read into its row, a changed row is written out, and both changed is yours to settle")
        rescue Sqlite::Error => e
          raise Failure, e.message
        end

        private

        def switches(parser)
          parser.on("--dry-run") { options[:dry_run] = true }
        end

        def refuse(home, conflicts)
          return if conflicts.empty?

          diffs = conflicts.map { |path| "#{path}\n#{StoreSync.diff(home, path)}" }
          raise Refusal, "the file and the row both changed; nothing was written\n#{diffs.join("\n")}"
        end

        def apply(home, plan)
          (plan == [["build", SearchIndex::NAME]]) ? SearchIndex.build(home) : StoreSync.apply(home, plan)
          WorkGraph.build(home)
          ReferenceArchive.build(home)
        end
      end
    end
  end
end
