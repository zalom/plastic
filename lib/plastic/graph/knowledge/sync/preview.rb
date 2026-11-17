# frozen_string_literal: true

require "fileutils"
require "find"
require "tmpdir"
require_relative "preview/mirror"
require_relative "preview/changes"
require_relative "../legacy/unguarded"
require_relative "../../../config"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # A dry run of a sync: the lines of what it would do, on a copy of the store.
        class Preview
          # The lines of a dry run, and what the real sync would refuse: the files changed on both sides, whether
          # it merges, the intent folders it cannot read, and each changed file no reader turns into rows, with the reason, and which of those files this home holds no rows for.
          Run = Data.define(:lines, :conflicts, :merging, :unreadable, :unreadable_files, :rowless_files)

          def initialize(home, store, options, direction: :up)
            @home, @store, @options, @direction = home, store, options, direction
          end

          def self.conflict_lines(plan) = plan.conflicts.map { |path| "conflict: #{path}" }

          def call = preview.lines

          def preview
            found = Dir.mktmpdir("plastic-sync-preview", parent_dir) { |copy| run_in(copy) }
            found.with(lines: found.lines.map { |line| "preview: #{line}" })
          end

          private

          def options
            overwrite = @options[:overwrite]
            overwrite = overwrite.delete_prefix("#{source}/") if overwrite.is_a?(String)
            @options.merge(overwrite:)
          end

          def source = File.join(@home, "stores", @store)

          def check_source
            return unless File.exist?(source)

            Find.find(source) do |path|
              raise Invalid, "preview cannot copy symbolic link #{path}; the original store was not changed" if File.symlink?(path)
            end
          end

          def parent_dir = File.directory?(@home) ? @home : Dir.tmpdir

          def run_in(copy)
            twin = copy_source(copy)
            applied = applied_in(copy)
            changes = Changes.new(source, twin).call
            applied.with(lines: [*applied.lines, *changes, "paths that would change: #{changes.size}"])
          end

          def applied_in(copy)
            work = Graph.open(home: copy, store: @store).work
            plan = checked(work.sync_plan(@direction, options))
            lines = [*Preview.conflict_lines(plan), *work.sync_apply(plan, rollback: Legacy::Unguarded)]
            Run.new(lines:, conflicts: plan.conflicts, merging: plan.merging?, **refused(work, plan))
          end

          # What the real sync up refuses after its apply; a sync down refuses none of it.
          def refused(work, plan)
            return { unreadable: [], unreadable_files: {}, rowless_files: [] } unless @direction == :up

            after = work.sync_plan(@direction, options)
            { unreadable: plan.unreadable, unreadable_files: after.unreadable_files, rowless_files: after.rowless_files }
          end

          def checked(plan)
            failure = plan.failure
            raise Invalid, failure if failure

            plan
          end

          def copy_source(copy)
            check_source
            copy_home_files(copy)
            File.join(copy, "stores", @store).tap { |twin| Mirror.new(source, twin).call }
          end

          def copy_home_files(copy)
            %w[origin_id projects.yml].each do |name|
              path = File.join(@home, name)
              FileUtils.cp(path, copy) if File.file?(path)
            end
            Config::Store.new(copy).copy_rows_from(@home)
            Config.new(copy).set("migrate.remove_after_import", false)
          end
        end
      end
    end
  end
end
