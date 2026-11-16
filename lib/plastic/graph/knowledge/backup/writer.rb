# frozen_string_literal: true

require "fileutils"
require_relative "../backup"
require_relative "copy"
require_relative "folder_name"
require_relative "folders"
require_relative "source_check"

module Plastic
  module Graph
    module Knowledge
      class Backup
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

          def initialize(store_root, slug, now:, databases: nil, copy: Copy.new(now:, databases:), automatic: false, reason: nil)
            @root = store_root
            @slug = slug
            @now = now
            @copy = copy
            @automatic = automatic
            @reason = reason
          end

          # The backup row, or nil when an automatic backup had nothing to do.
          def call
            check = source_check
            version = check.version
            return if @automatic && unchanged?(check)

            folder = claim
            folder && write(folder, extra(check, version))
          rescue SourceCheck::Failed => error
            raise Error, error.message
          end

          private

          def folders = (@folders ||= Folders.new(@root))

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
            @automatic ? take(FolderName.timestamp(@now)) : take(FolderName.for(folders.dir, @now))
          rescue Errno::EEXIST
            nil
          end

          def take(name) = Dir.mkdir(folders.path(name)) && name

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
end
