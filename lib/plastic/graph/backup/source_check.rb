# frozen_string_literal: true

require "sqlite3"
require_relative "../backup"

module Plastic
  module Graph
    module Backup
      # Reads the live store files before a copy: each must pass SQLite's
      # quick check, and the lowest schema version among them is the
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

        # The lowest user_version of the files; raises Failed when one file is damaged.
        def version = @paths.map { |path| inspect_file(path) }.min

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
