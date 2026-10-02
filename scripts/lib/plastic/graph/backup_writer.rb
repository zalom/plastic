# frozen_string_literal: true

require "rubygems/package"
require "zlib"
require "digest"
require "fileutils"
require "tmpdir"
require_relative "database"
require_relative "schema"
require_relative "tar_entry_writer"

module Plastic
  module Graph
    # Packs home.db and every store's three databases into one gzipped tar
    # under backups/. Each database is snapshotted with VACUUM INTO into a
    # temporary folder before packing, so a writer elsewhere never corrupts
    # the archive. An entry name too long for a USTAR header gets a GNU
    # long-name header first, so a long store name or a deep home path
    # never stops the write.
    class BackupWriter
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

      # Writes the archive and returns the row to save.
      def call
        at = Plastic.now
        name = "plastic-#{Time.now.strftime("%Y%m%d-%H%M%S")}.tar.gz"
        path = File.join(backups_dir, name)
        files = pack(path)
        { name:, files:, bytes: File.size(path), sha256: Digest::SHA256.file(path).hexdigest, at:, session_id: @session }
      end

      private

      def backups_dir = File.join(@home, "backups").tap { |dir| FileUtils.mkdir_p(dir) }

      def sources
        [["home.db", File.join(@home, "home.db")]] + store_sources
      end

      def store_sources
        Dir.glob(File.join(@home, "stores", "*")).select { |path| File.directory?(path) }.sort.flat_map do |store|
          store_entries(store)
        end
      end

      def store_entries(store)
        slug = File.basename(store)
        Schema::STORE.filter_map { |key| self.class.store_entry(store, slug, key) }
      end

      def pack(path)
        entries = sources
        writer = self.class
        Dir.mktmpdir("plastic-backup") { |tmp| writer.write_tar(path, writer.vacuum(tmp, entries)) }
        entries.size
      end
    end
  end
end
