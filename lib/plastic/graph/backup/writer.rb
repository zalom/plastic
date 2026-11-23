# frozen_string_literal: true

require "fileutils"
require_relative "../backup"
require_relative "copy"
require_relative "folder_name"
require_relative "folders"
require_relative "site"
require_relative "source_check"

module Plastic
  module Graph
    module Backup
      # Copies the store databases into a new backup folder with VACUUM INTO,
      # so a writer elsewhere never corrupts the copy. Every live database is
      # checked first, and none is copied when one fails. The folder carries a
      # status file: in-progress before the first copy, done after the last,
      # failed when a copy fails, with the schema version, the fingerprint of
      # the live files, the reason, and the time it was taken in UTC. An
      # automatic backup writes nothing when the store is unchanged since the
      # newest backup, or when another session took the folder first. A
      # database that does not exist is never created.
      class Writer
        # Nothing to copy, or a database that cannot be trusted.
        class Error < StandardError; end

        MODE_KEYS = %i[automatic reason].freeze

        # Whether the backup is automatic, and the reason that asked for it.
        Mode = Data.define(:automatic, :reason)

        def initialize(store_root, slug, now:, copy: Copy.new(now:), **mode)
          @site = Site.new(store_root, slug)
          @now = now
          @copy = copy
          unknown = mode.keys - MODE_KEYS
          raise ArgumentError, "unknown keyword: #{unknown.first}" if unknown.any?

          @mode = Mode.new(mode.fetch(:automatic, false), mode[:reason])
        end

        # The backup row, or nil when an automatic backup had nothing to do.
        def call
          check = source_check
          return if @mode.automatic && claimed_lately?

          folder = claim
          folder && checked_write(folder, check)
        end

        private

        # The claim comes before the check, so a second session finds it; it goes when the check fails or the store is unchanged.
        def checked_write(folder, check)
          version = verified(check, folder)
          return release(folder) if @mode.automatic && unchanged?(check, folder)

          write(folder, extra(check, version))
        rescue SourceCheck::Unreadable => error
          raise Error, error.message
        end

        def release(folder) = Dir.rmdir(folders.path(folder)) && nil

        def claimed_lately?
          newest = folders.latest
          !newest.nil? && folders.status(newest) != "done" && (@now - FolderName.time(newest)).between?(0, Folders::CLAIM_WINDOW)
        end

        def folders = @site.folders

        def stamp = Plastic.timestamp(@now)

        # The lowest version of the live files; each check is recorded for the doctor.
        def verified(check, folder)
          check.version.tap { folders.write_check(at: stamp, verdict: "passed") }
        rescue SourceCheck::Unreadable => error
          folders.write_check(at: stamp, verdict: "failed", file: File.basename(error.path), reason: error.message)
          release(folder)
          raise
        end

        def source_check
          root = @site.root
          names = @copy.sources(root)
          raise Error, "no store database to back up in #{root}" if names.empty?

          SourceCheck.new(names.map { |name| File.join(root, "#{name}.db") })
        end

        def unchanged?(check, own)
          newest = folders.latest { |name| name != own }
          !newest.nil? && folders.report(newest)["fingerprint"] == check.fingerprint
        end

        def claim
          dir = folders.dir
          FileUtils.mkdir_p(dir)
          claim_folder(@mode.automatic ? FolderName.timestamp(@now) : FolderName.for(dir, @now))
        rescue Errno::EEXIST
          nil
        end

        def claim_folder(name) = Dir.mkdir(folders.path(name)) && name

        def extra(check, version) = { version:, fingerprint: check.fingerprint, reason: @mode.reason, taken_at: stamp }.compact

        def write(folder, extra)
          @copy.call(Copy::Slot.new(@site.root, folders, folder, nil, extra))
          folders.record_digest(folder)
          @site.row(folder, stamp)
        end
      end
    end
  end
end
