# frozen_string_literal: true

require "sqlite3"
require_relative "../backup"
require_relative "../schema"
require_relative "../schema/state"

module Plastic
  module Graph
    module Backup
      # Reads the live store files before a copy: each must pass SQLite's
      # quick check, and the newest version the knowledge database records
      # is the version the backup records. The fingerprint is the size and change
      # time of each file, so an unchanged store can be told apart.
      class SourceCheck
        # A live database failed its quick check.
        class Unreadable < StandardError
          attr_reader :path

          def initialize(message, path)
            super(message)
            @path = path
          end
        end

        def self.describe(path)
          mtime = File.mtime(path)
          "#{File.basename(path)} #{File.size(path)} #{mtime.to_i}.#{mtime.nsec}"
        end

        def initialize(paths)
          @paths = paths
        end

        # The version the knowledge database of the store records; raises Unreadable when one file is damaged.
        def version
          stamps = @paths.to_h { |path| [path, inspect_file(path)] }
          knowledge = File.join(File.dirname(@paths.first), Schema.file(:knowledge))
          stamps.fetch(knowledge) { File.file?(knowledge) ? inspect_file(knowledge) : stamps.values.min }
        end

        def fingerprint
          @paths.map { |path| self.class.describe(path) }.join("\n")
        end

        private

        def inspect_file(path)
          SQLite3::Database.open(path, readonly: true) do |database|
            (database.get_first_value("PRAGMA quick_check") == "ok") || raise(Unreadable.new("#{path} fails the quick check", path))
            SchemaState.new(database, :store).call.number
          end
        rescue SQLite3::Exception => error
          raise Unreadable.new("#{path} cannot be read: #{error.message}", path)
        end
      end
    end
  end
end
