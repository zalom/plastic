# frozen_string_literal: true

require_relative "../store_layout"

module Plastic
  module Installations
    # Removes the leftovers of the retired per-session day pointer and the
    # retired inter-hook key. A leftover is real only when it is reached with
    # no symbolic link between the Plastic home and it, and only a regular
    # file is ever removed. Nothing is opened or parsed: a torn leftover goes
    # by its name like a whole one. A failed delete warns once and the sync
    # goes on. Returns the count removed.
    class RetiredSessionState
      TMP_NAME = %r{\Aplastic-[^/]+--[^/]+\.json\z}n

      def initialize(home, tmp_dirs)
        @home = home
        @tmp_dirs = Array(tmp_dirs).compact
      end

      def call = candidates.uniq.count { |path| regular?(path) && delete(path) }

      private

      def candidates
        store_roots.flat_map { |root| current_files(root) } + @tmp_dirs.flat_map { |dir| tmp_files(dir) }
      end

      def store_roots
        stores = [StoreLayout.global_store(@home)] + Dir.glob(File.join(StoreLayout.projects_root(@home), "*", "store"))
        stores.uniq.select { |root| real?(root) }
      end

      def real?(root)
        File.realpath(root) == File.join(File.realpath(@home), root.delete_prefix("#{@home}/"))
      rescue SystemCallError
        false
      end

      def current_files(root)
        tmp = File.join(root, ".tmp")
        return [] unless File.lstat(tmp).directory?

        Dir.children(tmp).map { |child| File.join(tmp, child) }.select { |dir| File.lstat(dir).directory? }.map { |dir| File.join(dir, "current") }
      rescue SystemCallError
        []
      end

      def tmp_files(dir)
        real = File.realpath(dir)
        Dir.children(real).select { |name| name.b.match?(TMP_NAME) }.map { |name| File.join(real, name) }
      rescue SystemCallError
        []
      end

      def regular?(path)
        File.lstat(path).file?
      rescue SystemCallError
        false
      end

      def delete(path)
        File.delete(path)
        true
      rescue SystemCallError => error
        warn "   Could not remove retired session state #{path}: #{error.message}"
        false
      end
    end
  end
end
