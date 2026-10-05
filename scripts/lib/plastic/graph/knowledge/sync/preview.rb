# frozen_string_literal: true

require "fileutils"
require "find"
require "tmpdir"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # Runs the real sync against a disposable copy of one store.
        class Preview
          def initialize(home, store, options, direction: :up)
            @home, @store, @options, @direction = home, store, options, direction
          end

          def self.conflict_lines(plan) = plan.conflicts.map { |path| "conflict: #{path}" }

          def call = Dir.mktmpdir("plastic-sync-preview") { |copy| lines_in(copy) }.map { |line| "preview: #{line}" }

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

          def lines_in(copy)
            copy_source(copy)
            work = Graph.open(home: copy, store: @store).work
            plan = checked(work.sync_plan(@direction, options))
            [*Preview.conflict_lines(plan), *work.sync_apply(plan)]
          end

          def checked(plan)
            failure = plan.failure
            raise Invalid, failure if failure

            plan
          end

          def copy_source(copy)
            check_source
            copy_home_files(copy)
            copy_store(copy)
          end

          def copy_home_files(copy)
            %w[origin_id config.yml projects.yml].each do |name|
              path = File.join(@home, name)
              FileUtils.cp(path, copy) if File.file?(path)
            end
          end

          def copy_store(copy)
            parent = File.join(copy, "stores")
            FileUtils.mkdir_p(parent)
            FileUtils.cp_r(source, File.join(parent, @store)) if File.directory?(source)
          end
        end
      end
    end
  end
end
