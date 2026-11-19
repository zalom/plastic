# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "front_matter"
require_relative "intent"
require_relative "store_path"
require_relative "sync_settings"

module Plastic
  module Graph
    module Knowledge
      # The files of one store folder, by path relative to it. The folder holds
      # its databases, INDEX.md in a store not yet imported, store/index.json,
      # and one folder per intent under store/.
      class StoreFolder
        INDEX = "store/index.json"
        LEGACY_INDEX = "INDEX.md"
        IGNORE_FILE = ".gitignore"
        IGNORED = %w[*.db *.db-journal backups/].freeze
        # Machine state of the command line that runs today, never a record.
        SKIPPED = /\A(?:delivery\.lock|\.DS_Store)\z/

        attr_reader :root, :sync

        def initialize(root, sync: SyncSettings.none)
          @root = root
          @sync = sync
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

        def own_file(dir)
          fixed = "#{dir}/#{Intent::FILE}"
          exist?(fixed) ? fixed : "#{dir}/#{File.basename(dir)}.md"
        end

        # Every roadmap file on disk, by path. The event log an older release kept beside a roadmap is not one.
        def roadmap_files = Dir.glob("roadmaps/*.md", base: root).reject { |path| StorePath.roadmap_log?(path) }.sort

        def intent_dirs = Dir.glob("store/*--*/", base: root).map { |dir| dir.chomp("/") }.sort

        # Every file of every intent folder that the selection reads, dot files included.
        def intent_files = intent_dirs.flat_map { |dir| files(dir) }

        def files(dir)
          intent_id = SyncSelection.intent_of(dir)
          selected = Dir.glob("**/*", File::FNM_DOTMATCH, base: path(dir)).select { |rel| @sync.selection.read?(rel, intent_id:) }
          selected.map { |rel| "#{dir}/#{rel}" }.select { |rel| kept?(rel) }.sort
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
end
