# frozen_string_literal: true

require "sqlite3"
require_relative "../backup"
require_relative "../schema"

module Plastic
  module Graph
    module Backup
      # Reads the live store files before a copy: each must pass SQLite's
      # quick check, and the stamp of the knowledge database is the
      # version the backup records. The fingerprint is the size and change
      # time of each file, so an unchanged store can be told apart.
      class SourceCheck
        # A live database failed its quick check.
        class Failed < StandardError
          attr_reader :path

          def initialize(message, path)
            super(message)
            @path = path
          end
        end

        def initialize(paths)
          @paths = paths
        end

        # The user_version of the knowledge database of the store, which stamps it; raises Failed when one file is damaged.
        def version
          stamps = @paths.to_h { |path| [path, inspect_file(path)] }
          knowledge = File.join(File.dirname(@paths.first), Schema.file(:knowledge))
          stamps.fetch(knowledge) { File.file?(knowledge) ? inspect_file(knowledge) : stamps.values.min }
        end

        def fingerprint
          @paths.map do |path|
            stat = File.stat(path)
            "#{File.basename(path)} #{stat.size} #{stat.mtime.to_i}.#{stat.mtime.nsec}"
          end.join("\n")
        end

        private

        def inspect_file(path)
          SQLite3::Database.open(path, readonly: true) do |database|
            (database.get_first_value("PRAGMA quick_check") == "ok") || raise(Failed.new("#{path} fails the quick check", path))
            database.get_first_value("PRAGMA user_version")
          end
        rescue SQLite3::Exception => error
          raise Failed.new("#{path} cannot be read: #{error.message}", path)
        end
      end
    end
  end
end
