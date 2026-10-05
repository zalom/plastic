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
          def self.vacuum(source, target) = Database::ConnectionPool.for(source).execute("VACUUM INTO ?", [target])

          def initialize(now:, databases: nil, copier: self.class.method(:vacuum), live: ->(_line) {})
            @now = now
            @databases = databases
            @copier = copier
            @live = live
          end

          # The databases of the store this copy would take, by name.
          def sources(root) = Databases.chosen(@databases).select { |name| File.file?(File.join(root, "#{name}.db")) }

          # Copies each source into the folder: in-progress, then done, or error with the reason in the log.
          def call(root, folders, folder)
            log = Log.new(folders.path(folder), now: @now, live: @live)
            report(folders, folder, "in-progress")
            bytes = each_copy(root, folders.path(folder), folder, log)
            log.done(sources(root).size, bytes)
            report(folders, folder, "done")
          rescue => error
            log.failed(error.message)
            report(folders, folder, "error")
            raise
          end

          private

          def report(folders, folder, status) = folders.write_report(folder, status:, goal: Databases.goal(@databases))

          def each_copy(root, path, folder, log)
            sources(root).sum do |name|
              target = File.join(path, "#{name}-#{folder}.db")
              @copier.call(File.join(root, "#{name}.db"), target)
              File.size(target).tap { |size| log.database(name, size) }
            end
          end
        end
      end
    end
  end
end
