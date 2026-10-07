# frozen_string_literal: true

require "fileutils"
require "find"
require_relative "../schema"
require_relative "snapshot"

module Plastic
  module Graph
    class DisposableCopy
      # The files of one home and one store, copied under another path, and
      # what the copy looked like when it was made. Every copied file gets
      # the epoch as its time, so a file written in the copy shows as changed
      # even when its bytes did not.
      class StoreTree
        EPOCH = Time.at(0)
        DATABASE = Snapshot::DATABASE
        HOME_FILES = %w[origin_id config.yml projects.yml].freeze

        def initialize(home, copy, slug)
          @home = home
          @copy = copy
          @slug = slug
          @baseline = nil
        end

        def populate
          refuse_folder_links
          FileUtils.mkdir_p(@copy)
          copy_all
          @baseline = state
          self
        end

        def changes = Snapshot.differences(@baseline, state).map { |verb, rel| [verb, File.join(@home, rel)] }

        def self.copy_file(source, target)
          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.cp(source, target)
          File.utime(EPOCH, EPOCH, target)
        end

        private

        def copy_all
          copy_home_files
          copy_store_files
          snapshot_databases
        end

        def source_root = File.join(@home, "stores", @slug)

        def refuse_folder_links
          return unless File.exist?(source_root) || File.symlink?(source_root)

          Find.find(source_root) do |path|
            raise Refused, "preview cannot copy folder link #{path}; the original store was not changed" if File.symlink?(path) && File.directory?(path)
          end
        end

        def copy_home_files
          HOME_FILES.each do |name|
            source = File.join(@home, name)
            StoreTree.copy_file(source, File.join(@copy, name)) if File.file?(source)
          end
        end

        def copy_store_files
          return unless File.directory?(source_root)

          Find.find(source_root) { |path| copy_entry(path) }
        end

        def copy_entry(path) = place(path, File.join(@copy, path.delete_prefix("#{@home}/")))

        def place(path, target)
          link = File.symlink?(path)
          return FileUtils.mkdir_p(target) if File.directory?(path) && !link
          return if DATABASE.match?(path)

          link ? copy_link(path, target) : StoreTree.copy_file(path, target)
        end

        def copy_link(source, target)
          held = File.join(File.dirname(@copy), "sandbox", target.delete_prefix("#{@copy}/"))
          File.file?(source) ? StoreTree.copy_file(source, held) : FileUtils.mkdir_p(File.dirname(held))
          FileUtils.mkdir_p(File.dirname(target))
          File.symlink(held, target)
        end

        def snapshot_databases
          sources.each do |name, source|
            target = File.join(@copy, name)
            FileUtils.mkdir_p(File.dirname(target))
            Database::ConnectionPool.for(source).execute("VACUUM INTO ?", [target])
          end
        end

        def sources
          store = Schema.store.filter_map { |key| store_entry(key) }
          [local_entry, *store].compact
        end

        def local_entry
          [Schema.file(:local), "home.db"].map { |file| [file, File.join(@home, file)] }.find { |_file, path| File.file?(path) }
        end

        def store_entry(key)
          file = Schema.file(key)
          path = File.join(source_root, file)
          ["stores/#{@slug}/#{file}", path] if File.exist?(path)
        end

        def state = Snapshot.of(@copy)
      end
    end
  end
end
