# frozen_string_literal: true

require "digest"
require "fileutils"

module Plastic
  module Graph
    # The files of one store folder, by path relative to it. The folder holds
    # its databases, INDEX.md in a store not yet imported, store/index.json,
    # and one folder per intent under store/.
    class StoreFolder
      INDEX = "store/index.json"
      LEGACY_INDEX = "INDEX.md"
      IGNORE_FILE = ".gitignore"
      IGNORED = %w[*.db *.db-journal].freeze
      # Machine state of the command line that runs today, never a record.
      SKIPPED = /(?:\.lock|\A\.DS_Store)\z/

      attr_reader :root

      def initialize(root)
        @root = root
      end

      def path(rel) = File.join(root, rel)

      def exist?(rel) = File.file?(path(rel))

      def read(rel) = File.binread(path(rel))

      # The SHA-256 of the file, or nil when it is gone.
      def digest(rel) = exist?(rel) ? Digest::SHA256.file(path(rel)).hexdigest : nil

      # A store with INDEX.md and no store/index.json has not been imported yet.
      def legacy? = exist?(LEGACY_INDEX) && !exist?(INDEX)

      # Writes the whole file under a temporary name first, so a reader never sees half of it.
      def write(rel, bytes)
        full = path(rel)
        FileUtils.mkdir_p(File.dirname(full))
        draft = "#{full}.#{Process.pid}.tmp"
        File.binwrite(draft, bytes)
        File.rename(draft, full)
      end

      def delete(rel) = FileUtils.rm_f(path(rel))

      # Removes a whole folder of the checkout, such as an archived intent's.
      def remove_dir(rel) = FileUtils.rm_rf(path(rel))

      def intent_dirs = Dir.glob("store/*--*/", base: root).map { |dir| dir.chomp("/") }.sort

      # Every file of every intent folder, dot files included.
      def intent_files = intent_dirs.flat_map { |dir| files(dir) }

      def files(dir)
        Dir.glob("**/*", File::FNM_DOTMATCH, base: path(dir)).map { |rel| "#{dir}/#{rel}" }.select { |rel| kept?(rel) }.sort
      end

      # The store's versioning never holds its databases.
      def ignore_databases
        lines = exist?(IGNORE_FILE) ? read(IGNORE_FILE).lines(chomp: true) : []
        missing = IGNORED - lines
        write(IGNORE_FILE, (lines + missing).map { |line| "#{line}\n" }.join) if missing.any?
      end

      private

      def kept?(rel) = File.file?(path(rel)) && !File.basename(rel).match?(SKIPPED)
    end
  end
end
