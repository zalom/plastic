# frozen_string_literal: true

require_relative "../backup"
require_relative "../../database"
require_relative "databases"
require_relative "log"

module Plastic
  module Graph
    module Knowledge
      class Backup
        # The copy of the store databases into one backup folder, with the
        # folder's status file and its backup.log. The copy step is passed in
        # so a test can watch the log between two copies, and the live sink
        # gets each log line as it is written.
        class Copy
          # Where one backup goes: the store root, the folders of the store and the new folder's name, and its log once the copy starts.
          Slot = Struct.new(:root, :folders, :folder, :log) do
            def path = folders.path(folder)

            def source(name) = File.join(root, "#{name}.db")

            def target(name) = File.join(path, "#{name}-#{folder}.db")

            # Copies each named database and logs its line; gives the bytes copied.
            def copy_all(names, copier) = names.sum { |name| copy(name, copier).tap { |size| log.database(name, size) } }

            def write_status(status, goal) = folders.write_report(folder, status:, goal:)

            # Copies one database with the step passed in, and gives the size of the copy.
            def copy(name, copier)
              File.size(target(name).tap { |to| copier.call(source(name), to) })
            end
          end

          def self.vacuum(source, target) = Database::ConnectionPool.for(source).execute("VACUUM INTO ?", [target])

          def initialize(now:, databases: nil, copier: self.class.method(:vacuum), live: ->(_line) {})
            @now = now
            @databases = databases
            @copier = copier
            @live = live
          end

          # The databases of the store this copy would take, by name.
          def sources(root) = Databases.chosen(@databases).select { |name| File.file?(File.join(root, "#{name}.db")) }

          # Copies each source into the folder: in-progress, then done, or failed with the reason in the log.
          def call(slot)
            slot.log = Log.new(slot.path, now: @now, live: @live)
            copy_into(slot)
          rescue => error
            fail_with(slot, error)
            raise
          end

          private

          def copy_into(slot)
            report(slot, "in-progress")
            names = sources(slot.root)
            slot.log.done(names.size, slot.copy_all(names, @copier))
            report(slot, "done")
          end

          def report(slot, status) = slot.write_status(status, Databases.goal(@databases))

          def fail_with(slot, error)
            slot.log.failed(error.message)
            report(slot, "failed")
          end
        end
      end
    end
  end
end
