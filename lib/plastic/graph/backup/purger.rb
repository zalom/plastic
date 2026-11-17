# frozen_string_literal: true

require "fileutils"
require_relative "../backup"
require_relative "folder_name"
require_relative "folders"

module Plastic
  module Graph
    module Backup
      # Deletes backups of one store. The folders on disk decide what
      # exists; a folder goes with its row, a row with no folder goes alone.
      class Purger
        RETENTION = 3 * 24 * 60 * 60

        def initialize(local_db, store_root, slug)
          @local_db = local_db
          @slug = slug
          @folders = Folders.new(store_root)
        end

        # The folder names, all of them or those strictly before a time.
        def names(older_than: nil)
          @folders.names.select { |name| FolderName.before?(name, older_than) }
        end

        # The folders older than three days, except the newest backup the runner took before a migration.
        def expired(now:)
          kept = @folders.names.reverse.find { |name| @folders.report(name)["reason"] == "migration" }
          names(older_than: now - RETENTION).reject { |name| name == kept }
        end

        # The names of the folders whose backup failed.
        def failed = @folders.names.select { |name| @folders.status(name) == "failed" }

        # The names of this store's rows that have no folder.
        def orphans(older_than: nil)
          row_names.reject { |name| @folders.exist?(name) }.select { |name| FolderName.before?(name, older_than) }
        end

        # Deletes the folder and its row, or neither.
        def remove(name)
          aside = move_aside(name)
          delete_row(name)
          FileUtils.rm_rf(aside) if aside
        rescue
          File.rename(aside, @folders.path(name)) if aside
          raise
        end

        private

        def row_names
          prefix = "#{@slug}/"
          @local_db.rows("SELECT name FROM backups").map { |row| row.fetch("name") }.select { |name| name.start_with?(prefix) }.map { |name| name.delete_prefix(prefix) }
        end

        def move_aside(name)
          return unless @folders.exist?(name)

          File.join(@folders.dir, ".#{name}.purging").tap { |aside| File.rename(@folders.path(name), aside) }
        end

        def delete_row(name) = @local_db.transaction { |batch| batch.remove(:backups, name: "#{@slug}/#{name}") }
      end
    end
  end
end
