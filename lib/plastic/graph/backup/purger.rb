# frozen_string_literal: true

require "fileutils"
require_relative "../backup"
require_relative "folder_name"
require_relative "folders"

module Plastic
  module Graph
    module Backup
      # Deletes backups of one store. The folders on disk decide what
      # exists. A backup expires after three days, or after one day under
      # the daily backups.
      class Purger
        RETENTION = 3 * 24 * 60 * 60
        DAILY_RETENTION = 24 * 60 * 60
        # A run that stopped leaves its backup in-progress, or with no status recorded: no status file, an empty or unreadable one, or one with no status in it.
        STOPPED_STATUSES = %w[in-progress unknown].freeze

        def initialize(store_root, retention: RETENTION)
          @folders = Folders.new(store_root)
          @retention = retention
        end

        # The folder names, all of them or those strictly before a time.
        def names(older_than: nil)
          @folders.names.select { |name| FolderName.before?(name, older_than) }
        end

        # The folders older than the retention, except the newest backup the runner took before a migration.
        def expired(now:)
          kept = @folders.latest { |name| @folders.report(name)["reason"] == "migration" }
          names(older_than: now - @retention).reject { |name| name == kept }
        end

        # Deletes the expired folders, but keeps the newest backup that is done and the folders named in keep.
        def sweep(now:, keep: [])
          newest_done = @folders.latest { |name| @folders.status(name) == "done" }
          (expired(now:) - [newest_done] - keep).each { |name| remove(name) }
        end

        # The names of the folders whose backup failed.
        def failed = @folders.names.select { |name| @folders.status(name) == "failed" }

        # The names of the folders a run left behind: in-progress or with no status recorded, for longer than the claim window.
        def interrupted(now:)
          @folders.names.select { |name| STOPPED_STATUSES.include?(@folders.status(name)) && FolderName.before?(name, now - Folders::CLAIM_WINDOW) }
        end

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
