# frozen_string_literal: true

require "fileutils"
require_relative "../backup"
require_relative "copy"
require_relative "folder_name"
require_relative "folders"
require_relative "source_check"

module Plastic
  module Graph
    module Backup
      # Copies the store databases into a new backup folder with VACUUM INTO,
      # so a writer elsewhere never corrupts the copy. Every live database is
      # checked first, and none is copied when one fails. The folder carries a
      # status file: in-progress before the first copy, done after the last,
      # failed when a copy fails, with the schema version, the fingerprint of
      # the live files and the reason. An automatic backup writes nothing when
      # the store is unchanged since the newest backup, or when another session
      # took the folder first. A database that does not exist is never created.
      class Writer
        # Nothing to copy, or a database that cannot be trusted.
        class Error < StandardError; end

        MODE_KEYS = %i[automatic reason].freeze

        def initialize(store_root, slug, now:, copy: Copy.new(now:), **mode)
          @root = store_root
          @slug = slug
          @now = now
          @copy = copy
          unknown = mode.keys - MODE_KEYS
          raise ArgumentError, "unknown keyword: #{unknown.first}" if unknown.any?

          @automatic = mode.fetch(:automatic, false)
          @reason = mode[:reason]
        end

        # The backup row, or nil when an automatic backup had nothing to do.
        def call
          check = source_check
          version = verified(check)
          return if @automatic && unchanged?(check)

          folder = claim
          folder && write(folder, extra(check, version))
        rescue SourceCheck::Failed => error
          raise Error, error.message
        end

        private

        def folders = (@folders ||= Folders.new(@root))

        # The lowest version of the live files; each check is recorded for the doctor.
        def verified(check)
          check.version.tap { folders.write_check(at: Plastic.now(@now), verdict: "passed") }
        rescue SourceCheck::Failed => error
          folders.write_check(at: Plastic.now(@now), verdict: "failed", file: File.basename(error.path), reason: error.message)
          raise
        end

        def source_check
          names = @copy.sources(@root)
          raise Error, "no store database to back up in #{@root}" if names.empty?

          SourceCheck.new(names.map { |name| File.join(@root, "#{name}.db") })
        end

        def unchanged?(check)
          newest = folders.latest
          !newest.nil? && folders.report(newest)["fingerprint"] == check.fingerprint
        end

        def claim
          FileUtils.mkdir_p(folders.dir)
          @automatic ? claim_folder(FolderName.timestamp(@now)) : claim_folder(FolderName.for(folders.dir, @now))
        rescue Errno::EEXIST
          nil
        end

        def claim_folder(name) = Dir.mkdir(folders.path(name)) && name

        def extra(check, version) = { version:, fingerprint: check.fingerprint, reason: @reason }.compact

        def write(folder, extra)
          @copy.call(Copy::Slot.new(@root, folders, folder, nil, extra))
          row(folder)
        end

        def row(folder)
          { name: "#{@slug}/#{folder}", files: folders.files(folder).size, bytes: folders.bytes(folder),
            sha256: folders.digest(folder), at: Plastic.now(@now) }
        end
      end
    end
  end
end
