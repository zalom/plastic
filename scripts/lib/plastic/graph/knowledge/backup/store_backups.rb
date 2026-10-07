# frozen_string_literal: true

require_relative "databases"
require_relative "folders"
require_relative "publisher"
require_relative "purger"
require_relative "restorer"
require_relative "target"

module Plastic
  module Graph
    module Knowledge
      class Backup
        # The backups of one store as a call sees them: write one, preview
        # one, list, purge and restore. The clock is passed in.
        class StoreBackups
          # One line of the list: a folder, its row or both.
          Entry = Struct.new(:number, :folder, :started, :status, :goal, :flag)

          def initialize(home_db, store_root, slug, session: nil, clock: Time)
            @target = Target.new(home_db, store_root, slug, session)
            @clock = clock
          end

          def folders = @target.folders

          def write(databases: nil, live: ->(_line) {}) = Publisher.new(@target, now: @clock.now, databases:, live:).call

          # The folder a backup would be written to and the databases it would copy.
          def plan(databases: nil)
            held = Databases.chosen(databases).select { |name| File.file?(@target.file(name)) }
            { folder: FolderName.for(folders.dir, @clock.now), databases: held }
          end

          # This store's rows, oldest first.
          def rows = @target.home_db.rows("SELECT * FROM backups ORDER BY at").map { |row| Backup.from_h(row) }.select { |backup| backup.name.start_with?("#{@target.slug}/") }

          # Every folder and every row of this store, in the order of their names.
          def entries
            held = rows.to_h { |backup| [backup.folder, backup] }
            (folders.names | held.keys).sort.each_with_index.map { |name, index| entry(index + 1, name, held[name]) }
          end

          def purger = Purger.new(@target.home_db, @target.root, @target.slug)

          def restorer = Restorer.new(@target.home_db, @target.root, @target.slug, now: @clock.now, session: @target.session)

          # The newest folder marked done, or nil.
          def latest_done = folders.names.reverse.find { |name| folders.status(name) == "done" }

          def restore(timestamp, databases: nil) = restorer.call(timestamp, databases:)

          private

          def entry(number, name, backup)
            Entry.new(number, name, FolderName.time(name).localtime.strftime("%Y-%m-%d %H:%M:%S"),
              folders.status(name), folders.goal(name), flag(backup))
          end

          def flag(backup)
            return "no row" unless backup

            backup.flag(File.expand_path("../..", @target.root))
          end
        end
      end
    end
  end
end
