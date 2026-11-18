# frozen_string_literal: true

require "fileutils"
require_relative "files"

module Plastic
  module Installations
    # Deletes the files an earlier install listed and this one does not, and
    # the folders that empties. A path outside the roots is skipped, and a
    # path inside the intent stores is refused, whatever the roots are.
    class Prune
      STORE_FOLDERS = %w[store projects stores].freeze

      def initialize(home:, roots:)
        @store_roots = STORE_FOLDERS.map { |name| File.join(home, name) }
        @roots = Array(roots).compact.map { |root| File.expand_path(root) }
      end

      def call(stale) = Prune.delete(stale.select { |path| reachable?(path) })

      def self.delete(paths)
        removed = paths.count { |path| remove(path) }
        tidy(paths.map { |path| File.dirname(path) })
        removed
      end

      def self.remove(path)
        return false unless File.exist?(path)

        File.delete(path)
        true
      end

      def self.tidy(folders)
        folders.uniq.sort_by { |folder| -folder.length }.each do |folder|
          FileUtils.rmdir(folder) if File.directory?(folder) && Dir.empty?(folder)
        end
      end

      private

      def reachable?(path)
        return refuse("Refused to prune #{path}: inside the intent store") if Files.contained?(path, @store_roots)
        return true if Files.contained?(path, @roots)

        refuse("Skipped prune of #{path}: outside #{@roots.join(", ")}")
      end

      def refuse(message)
        warn "   #{message}"
        false
      end
    end
  end
end
