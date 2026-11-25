# frozen_string_literal: true

require_relative "databases"
require_relative "folders"
require_relative "publisher"
require_relative "purger"
require_relative "restorer"
require_relative "target"

module Plastic
  module Graph
    module Backup
      # The backups of one store as a call sees them: write one, preview
      # one, list, purge and restore. The clock is passed in.
      class StoreBackups
        # One line of the list: a folder and what its status file says of it.
        Entry = Struct.new(:number, :folder, :started, :status, :goal, :flag)

        def initialize(local_db, store_root, retrieval, session: nil, clock: Time)
          @target = Target.new(local_db, store_root, retrieval.store, session)
          @retrieval = retrieval
          @clock = clock
        end

        def folders = @target.folders

        def write(databases: nil, live: ->(_line) {}) = Publisher.new(@target, now: @clock.now, databases:, live:).call

        # The folder a backup would be written to and the databases it would copy.
        def plan(databases: nil)
          held = Databases.chosen(databases).select { |name| File.file?(@target.file(name)) }
          { folder: FolderName.for(folders.dir, @clock.now), databases: held }
        end

        # Every folder of this store, in the order of their names.
        def entries = folders.names.each_with_index.map { |name, index| entry(index + 1, name) }

        def purger = Purger.new(@target.root)

        # The current time of this call's clock.
        def now = @clock.now

        def restorer = Restorer.new(@target, @retrieval, now: @clock.now)

        # The newest folder marked done that holds a database file, or nil.
        def latest_done = folders.latest { |name| folders.status(name) == "done" && folders.files(name).any? }

        def restore(timestamp, databases: nil) = restorer.call(timestamp, databases:)

        # Rebuilds the search rows of every intent from the restored and migrated knowledge file.
        def rebuild_index = @retrieval.reindex

        private

        def entry(number, name)
          Entry.new(number, name, FolderName.started(name),
            folders.status(name), folders.goal(name), flag(name))
        end

        def flag(name)
          recorded = folders.report(name)["digest"]
          return "unverified" unless recorded

          (folders.digest(name) == recorded) ? nil : "changed"
        end
      end
    end
  end
end
