# frozen_string_literal: true

require_relative "../backup"
require "rubygems"
require "rubygems/package"
require "zlib"
require "digest"
require "fileutils"
require "securerandom"
require "tmpdir"
require_relative "../../database"
require_relative "../../schema"
require_relative "tar_entry_writer"
require_relative "staged"
require_relative "archive_name"

module Plastic
  module Graph
    module Knowledge
      class Backup
        # Packs home.db and every store's three databases into one gzipped tar
        # under backups/. Each database is snapshotted with VACUUM INTO into a
        # temporary folder before packing, so a writer elsewhere never corrupts
        # the archive. An entry name too long for a USTAR header gets a GNU
        # long-name header first, so a long store name or a deep home path
        # never stops the write.
        class Writer
          HOME_FILES = %w[origin_id config.yml projects.yml].freeze

          def initialize(home, session: nil)
            @home = home
            @session = session
          end

          # A snapshot of each source, taken with VACUUM INTO, so a writer
          # elsewhere during the pack never corrupts the archive.
          def self.vacuum(tmp, entries)
            entries.each_with_index.map do |(name, source), index|
              dest = File.join(tmp, index.to_s)
              Database::ConnectionPool.for(source).execute("VACUUM INTO ?", [dest])
              [name, dest]
            end
          end

          def self.store_entry(store, slug, key)
            file = Schema.file(key)
            db = File.join(store, file)
            ["stores/#{slug}/#{file}", db] if File.exist?(db)
          end

          def self.write_tar(path, snapshots)
            Zlib::GzipWriter.open(path) { |gz| write_entries(gz, snapshots) }
          end

          def self.write_entries(gz, snapshots)
            tar = Gem::Package::TarWriter.new(gz)
            writer = TarEntryWriter.new(tar, gz)
            snapshots.each { |name, dest| writer.add(name, File.binread(dest)) }
            tar.close
          end

          # Writes a complete archive to a private path. The work graph publishes
          # it only with the matching metadata transaction.
          def stage
            name = ArchiveName.for(@home)
            path = staging_path(name)
            stage_archive(name, path)
          rescue
            FileUtils.rm_f(path) if path
            raise
          end

          # Makes a complete staged archive visible under its unique final name.
          def publish(staged)
            staged.publish_to(backups_dir)
          end

          # Removes a staged or newly published archive after a failed transaction.
          def discard(staged)
            staged.discard_from(backups_dir)
          end

          # Describes a backup without creating the home, archive, or metadata.
          def self.plan(home)
            { name: ArchiveName.for(home), files: sources(home).count { |(_name, path)| File.file?(path) } }
          end

          def self.sources(home)
            [["home.db", File.join(home, "home.db")]] + store_sources(home)
          end

          def self.store_sources(home)
            Dir.glob(File.join(home, "stores", "*")).select { |path| File.directory?(path) }.sort.flat_map do |store|
              slug = File.basename(store)
              Schema.store.filter_map { |key| store_entry(store, slug, key) }
            end
          end

          private

          def backups_dir = File.join(@home, "backups").tap { |dir| FileUtils.mkdir_p(dir) }

          def staging_path(name) = File.join(backups_dir, ".#{name}.#{SecureRandom.hex(8)}.tmp")

          def stage_archive(name, path)
            files = pack(path)
            Staged.new(row: archive_row(name, files, path), path:)
          end

          def archive_row(name, files, path)
            { name:, files:, bytes: File.size(path), sha256: Digest::SHA256.file(path).hexdigest, at: Plastic.now, session_id: @session }
          end

          def sources = self.class.sources(@home)

          def home_files
            HOME_FILES.filter_map do |name|
              path = File.join(@home, name)
              [name, path] if File.file?(path)
            end
          end

          def pack(path)
            entries = sources
            writer = self.class
            Dir.mktmpdir("plastic-backup") { |tmp| writer.write_tar(path, writer.vacuum(tmp, entries) + home_files) }
            entries.size
          end
        end
      end
    end
  end
end
