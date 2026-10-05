# frozen_string_literal: true

require_relative "databases"
require_relative "folders"
require_relative "publisher"
require_relative "purger"
require_relative "restorer"

module Plastic
  module Graph
    module Knowledge
      class Backup
        # The backups of one store as a call sees them: write one, preview
        # one, list, purge and restore. The clock is passed in.
        class StoreBackups
          # One line of the list: a folder, its row or both.
          Entry = Struct.new(:number, :folder, :started, :status, :goal, :flag)

          attr_reader :folders

          def initialize(home_db, store_root, slug, session: nil, clock: Time)
            @home_db = home_db
            @root = store_root
            @slug = slug
            @session = session
            @clock = clock
            @folders = Folders.new(store_root)
          end

          def write(databases: nil) = Publisher.new(@home_db, @root, @slug, now: @clock.now, databases:, session: @session).call

          # The folder a backup would be written to and the databases it would copy.
          def plan(databases: nil)
            held = (databases || Databases.all).select { |name| File.file?(File.join(@root, "#{name}.db")) }
            { folder: FolderName.for(@folders.dir, @clock.now), databases: held }
          end

          # This store's rows, oldest first.
          def rows = @home_db.rows("SELECT * FROM backups ORDER BY at").map { |row| Backup.from_h(row) }.select { |backup| backup.name.start_with?("#{@slug}/") }

          # Every folder and every row of this store, in the order of their names.
          def entries
            held = rows.to_h { |backup| [backup.folder, backup] }
            (@folders.names | held.keys).sort.each_with_index.map { |name, index| entry(index + 1, name, held[name]) }
          end

          def purger = Purger.new(@home_db, @root, @slug)

          def restorer = Restorer.new(@home_db, @root, @slug, now: @clock.now, session: @session)

          # The newest folder marked done, or nil.
          def latest_done = @folders.names.reverse.find { |name| @folders.status(name) == "done" }

          def restore(timestamp, databases: nil) = restorer.call(timestamp, databases:)

          private

          def entry(number, name, backup)
            Entry.new(number, name, FolderName.time(name).localtime.strftime("%Y-%m-%d %H:%M:%S"),
              @folders.status(name), @folders.goal(name), flag(name, backup))
          end

          def flag(name, backup)
            return "no row" unless backup

            backup.flag(File.expand_path("../..", @root))
          end
        end
      end
    end
  end
end
