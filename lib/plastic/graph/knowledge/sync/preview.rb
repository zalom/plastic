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
          # The lines of a dry run, and what the real sync up would refuse: the intent folders it cannot read,
          # and each changed file no reader turns into rows, with the reason.
          Run = Data.define(:lines, :unreadable, :unreadable_files)

          def initialize(home, store, options, direction: :up)
            @home, @store, @options, @direction = home, store, options, direction
          end

          def self.conflict_lines(plan) = plan.conflicts.map { |path| "conflict: #{path}" }

          def self.printed_over_lines(plan) = plan.printed_over.map { |path| Graph::Prints.printed_over_line(path) }

          def call = run.lines

          def run
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
            lines = [*Preview.conflict_lines(plan), *work.sync_apply(plan, rollback: Legacy::Unguarded), *Preview.printed_over_lines(plan)]
            Run.new(lines:, **refused(work, plan))
          end

          # What the real sync up refuses after its apply; a sync down refuses none of it.
          def refused(work, plan)
            return { unreadable: [], unreadable_files: {} } unless @direction == :up

            { unreadable: plan.unreadable, unreadable_files: work.sync_plan(@direction, options).unreadable_files }
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
            %w[origin_id config.yml projects.yml].each do |name|
              path = File.join(@home, name)
              FileUtils.cp(path, copy) if File.file?(path)
            end
            Config.new(copy).set("migrate.remove_after_import", false)
          end
        end
      end
    end
  end
end
