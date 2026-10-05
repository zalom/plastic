# frozen_string_literal: true

require "fileutils"
require_relative "../backup"
require_relative "../../database"
require_relative "databases"
require_relative "folder_name"
require_relative "folders"

module Plastic
  module Graph
    module Knowledge
      class Backup
        # Copies the store databases into a new backup folder with VACUUM INTO,
        # so a writer elsewhere never corrupts the copy. The folder carries a
        # status file: in-progress before the first copy, done after the last,
        # error when a copy fails. A database that does not exist is never
        # created.
        class Writer
          # Nothing to copy.
          class Error < StandardError; end

          def initialize(store_root, slug, now:, databases: nil)
            @root = store_root
            @slug = slug
            @now = now
            @databases = databases
          end

          def call
            raise Error, "no store database to back up in #{@root}" if sources.empty?

            folder = FolderName.for(folders.dir, @now)
            FileUtils.mkdir_p(folders.path(folder))
            copy_all(folder)
            row(folder)
          end

          private

          def folders = (@folders ||= Folders.new(@root))

          def sources = Databases.chosen(@databases).select { |name| File.file?(File.join(@root, "#{name}.db")) }

          def report(folder, status) = folders.write_report(folder, status:, goal: Databases.goal(@databases))

          def copy_all(folder)
            report(folder, "in-progress")
            sources.each { |name| self.class.vacuum(File.join(@root, "#{name}.db"), File.join(folders.path(folder), "#{name}-#{folder}.db")) }
            report(folder, "done")
          rescue
            report(folder, "error")
            raise
          end

          def self.vacuum(source, target) = Database::ConnectionPool.for(source).execute("VACUUM INTO ?", [target])

          def row(folder)
            { name: "#{@slug}/#{folder}", files: folders.files(folder).size, bytes: folders.bytes(folder),
              sha256: folders.digest(folder), at: Plastic.now(@now) }
          end
        end
      end
    end
  end
end
