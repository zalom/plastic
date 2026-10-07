# frozen_string_literal: true

require "fileutils"
require_relative "../backup"
require_relative "copy"
require_relative "folder_name"
require_relative "folders"

module Plastic
  module Graph
    module Knowledge
      class Backup
        # Copies the store databases into a new backup folder with VACUUM INTO,
        # so a writer elsewhere never corrupts the copy. The folder carries a
        # status file: in-progress before the first copy, done after the last,
        # failed when a copy fails. A database that does not exist is never
        # created. Copy does the copying and keeps backup.log.
        class Writer
          # Nothing to copy.
          class Error < StandardError; end

          def initialize(store_root, slug, now:, databases: nil, copy: Copy.new(now:, databases:))
            @root = store_root
            @slug = slug
            @now = now
            @copy = copy
          end

          def call
            raise Error, "no store database to back up in #{@root}" if @copy.sources(@root).empty?

            folder = FolderName.for(folders.dir, @now)
            FileUtils.mkdir_p(folders.path(folder))
            @copy.call(Copy::Slot.new(@root, folders, folder))
            row(folder)
          end

          private

          def folders = (@folders ||= Folders.new(@root))

          def row(folder)
            { name: "#{@slug}/#{folder}", files: folders.files(folder).size, bytes: folders.bytes(folder),
              sha256: folders.digest(folder), at: Plastic.now(@now) }
          end
        end
      end
    end
  end
end
