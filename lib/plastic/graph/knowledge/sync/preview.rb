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
        # Runs the real sync against a disposable twin of one store, then names the files it would write.
        class Preview
          def initialize(home, store, options, direction: :up)
            @home, @store, @options, @direction = home, store, options, direction
          end

          def self.conflict_lines(plan) = plan.conflicts.map { |path| "conflict: #{path}" }

          def call = Dir.mktmpdir("plastic-sync-preview", parent_dir) { |copy| lines_in(copy) }.map { |line| "preview: #{line}" }

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

          def lines_in(copy)
            twin = copy_source(copy)
            work = Graph.open(home: copy, store: @store).work
            plan = checked(work.sync_plan(@direction, options))
            lines = [*Preview.conflict_lines(plan), *work.sync_apply(plan, rollback: Legacy::Unguarded)]
            changes = Changes.new(source, twin).call
            [*lines, *changes, "paths that would change: #{changes.size}"]
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
