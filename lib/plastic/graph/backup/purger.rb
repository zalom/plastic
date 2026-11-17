# frozen_string_literal: true

require "fileutils"
require_relative "../backup"
require_relative "folder_name"
require_relative "folders"

module Plastic
  module Graph
    module Backup
      # Deletes backups of one store. The folders on disk decide what
      # exists.
      class Purger
        RETENTION = 3 * 24 * 60 * 60

        def initialize(store_root)
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

        # Deletes the folder, or leaves it where it was.
        def remove(name)
          aside = move_aside(name)
          FileUtils.rm_rf(aside) if aside
        rescue
          File.rename(aside, @folders.path(name)) if aside
          raise
        end

        private

        def move_aside(name)
          return unless @folders.exist?(name)

          File.join(@folders.dir, ".#{name}.purging").tap { |aside| File.rename(@folders.path(name), aside) }
        end
      end
    end
  end
end
