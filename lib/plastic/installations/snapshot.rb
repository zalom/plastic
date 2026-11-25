# frozen_string_literal: true

require "fileutils"

module Plastic
  module Installations
    # A copy of the files one manifest lists, and of the manifest, taken before
    # an install so a failed check can put them back.
    class Snapshot
      Absent = Data.define do
        def restore = false
      end

      NONE = Absent.new

      def initialize(dir, manifest)
        @dir = dir
        @paths = [*manifest.files, manifest.path].select { |path| File.file?(path) }
      end

      def capture
        FileUtils.rm_rf(@dir)
        @paths.each { |path| Snapshot.copy(path, kept(path)) }
        self
      end

      def restore
        @paths.each { |path| Snapshot.copy(kept(path), path) }
      end

      def self.copy(from, to)
        FileUtils.mkdir_p(File.dirname(to))
        FileUtils.cp(from, to)
      end

      private

      def kept(path) = File.join(@dir, path)
    end
  end
end
