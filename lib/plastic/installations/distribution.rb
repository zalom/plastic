# frozen_string_literal: true

require "fileutils"
require_relative "core_files"
require_relative "manifest"
require_relative "package"
require_relative "prune"
require_relative "retired_session_state"

module Plastic
  module Installations
    # Copies the core files of a package into the Plastic home, writes the
    # version and the manifest, and prunes what an earlier install wrote and
    # this package no longer ships.
    class Distribution
      LAUNCHER_FOLDERS = %w[hooks bin exe].freeze

      def initialize(package, tmp_dirs: RetiredSessionState.folders(nil))
        @package = package
        @home = package.home
        @tmp_dirs = tmp_dirs
        @manifest = Manifest.new(File.join(@home, "manifest.json"))
      end

      def install = sync("Installing")

      def update = sync("Updating")

      private

      def sync(verb)
        puts "  #{verb} core files to #{@home}"
        former = @manifest.files
        copy
        listed = record
        pruned = Prune.new(home: @home, roots: @home).call(former - listed)
        clean_up
        puts "  Core files synced (v#{@package.version})#{", #{pruned} stale file(s) pruned" if pruned.positive?}"
      end

      def copy
        %w[. lib exe hooks].each { |folder| FileUtils.mkdir_p(File.join(@home, folder)) }
        files.each_value { |path| place(path) }
        File.write(File.join(@home, "VERSION"), "#{@package.version}\n")
        FileUtils.chmod(0o755, launchers)
      end

      def files = CoreFiles.new(@package.root, status_line: @package.choices.statusline?).call

      def place(path)
        source = File.join(@package.root, path)
        return unless File.exist?(source)

        target = File.join(@home, path)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(source, target)
      end

      def launchers = Dir.glob(LAUNCHER_FOLDERS.map { |folder| File.join(@home, folder, "*") }).select { |path| File.file?(path) }

      def record
        listed = [*files.values, "VERSION"].map { |path| File.join(@home, path) }.select { |path| File.exist?(path) }
        @manifest.write(listed, @package.clock.now)
        listed
      end

      def clean_up
        removed = RetiredSessionState.new(@home, @tmp_dirs).call
        puts "  #{removed} retired session state file(s) removed" if removed.positive?
        FileUtils.rm_f(File.join(@home, ".cache", "update-check.json"))
      end
    end
  end
end
