# frozen_string_literal: true

require "digest"
require "fileutils"
require "find"
require_relative "../schema"
require_relative "../knowledge/backup/writer"

module Plastic
  module Graph
    class DisposableCopy
      # The files of one home and one store, copied under another path, and
      # what the copy looked like when it was made. Every copied file gets
      # the epoch as its time, so a file written in the copy shows as changed
      # even when its bytes did not.
      class StoreTree
        EPOCH = Time.at(0)
        DATABASE = /\.db(?:-journal|-wal|-shm)?\z/

        def initialize(home, copy, slug)
          @home = home
          @copy = copy
          @slug = slug
        end

        def populate
          refuse_folder_links
          FileUtils.mkdir_p(@copy)
          copy_home_files
          copy_store_files
          snapshot_databases
          @baseline = state
          self
        end

        def changes
          now = state
          (@baseline.keys | now.keys).sort.filter_map do |rel|
            verb = verb(@baseline[rel], now[rel])
            [verb, File.join(@home, rel)] if verb
          end
        end

        private

        def source_root = File.join(@home, "stores", @slug)

        def refuse_folder_links
          return unless File.exist?(source_root) || File.symlink?(source_root)

          Find.find(source_root) do |path|
            raise Refused, "preview cannot copy folder link #{path}; the original store was not changed" if File.symlink?(path) && File.directory?(path)
          end
        end

        def copy_home_files
          Knowledge::Backup::Writer::HOME_FILES.each do |name|
            source = File.join(@home, name)
            copy_file(source, File.join(@copy, name)) if File.file?(source)
          end
        end

        def copy_store_files
          return unless File.directory?(source_root)

          Find.find(source_root) { |path| copy_entry(path) }
        end

        def copy_entry(path)
          target = File.join(@copy, path.delete_prefix("#{@home}/"))
          return FileUtils.mkdir_p(target) if File.directory?(path) && !File.symlink?(path)
          return if DATABASE.match?(path)

          File.symlink?(path) ? copy_link(path, target) : copy_file(path, target)
        end

        def copy_file(source, target)
          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.cp(source, target)
          File.utime(EPOCH, EPOCH, target)
        end

        def copy_link(source, target)
          held = File.join(File.dirname(@copy), "sandbox", target.delete_prefix("#{@copy}/"))
          File.file?(source) ? copy_file(source, held) : FileUtils.mkdir_p(File.dirname(held))
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
          home_db = File.join(@home, "home.db")
          store = Schema.store.filter_map { |key| Knowledge::Backup::Writer.store_entry(source_root, @slug, key) }
          [(["home.db", home_db] if File.file?(home_db)), *store].compact
        end

        def state
          Dir.glob("**/*", File::FNM_DOTMATCH, base: @copy).to_h do |rel|
            [rel, fingerprint(File.join(@copy, rel))]
          end.compact
        end

        def fingerprint(path)
          return unless File.file?(path) && !DATABASE.match?(path)

          [Digest::SHA256.file(path).hexdigest, File.mtime(path)]
        end

        def verb(before, now)
          return "would add" unless before
          return "would remove" unless now

          "would change" if before != now
        end
      end
    end
  end
end
