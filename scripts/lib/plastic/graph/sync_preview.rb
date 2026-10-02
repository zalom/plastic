# frozen_string_literal: true

require "fileutils"
require "find"
require "tmpdir"

module Plastic
  module Graph
    # Runs the real sync against a disposable copy of one store.
    class SyncPreview
      def initialize(home, store, options)
        @home, @store, @options = home, store, options
      end

      def call
        Dir.mktmpdir("plastic-sync-preview") do |copy|
          copy_source(copy)
          work = Graph.open(home: copy, store: @store).work
          plan = work.sync_plan(:up, options)
          check(plan)
          work.sync_apply(plan).map { |line| "preview: #{line}" }
        end
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

      def check(plan)
        raise Invalid, plan.failure if plan.failure
        raise Invalid, "conflicts: #{plan.conflicts.join(", ")}" if plan.conflicts.any? && !plan.merging?
      end

      def copy_source(copy)
        check_source
        %w[origin_id config.yml projects.yml].each do |name|
          path = File.join(@home, name)
          FileUtils.cp(path, copy) if File.file?(path)
        end
        parent = File.join(copy, "stores")
        FileUtils.mkdir_p(parent)
        FileUtils.cp_r(source, File.join(parent, @store)) if File.directory?(source)
      end
    end
  end
end
