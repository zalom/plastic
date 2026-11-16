# frozen_string_literal: true

require "fileutils"
require "sqlite3"

module Plastic
  module Graph
    # The copy of the home database taken before it migrates: the source is
    # checked, VACUUM INTO writes <home>/backups/local-<UTC timestamp>.db, and
    # the copy is checked too. It raises when any step fails, and a failed
    # copy is removed.
    class HomeCopy
      def initialize(path, folder, now)
        @path = path
        @target = File.join(folder, "local-#{now.utc.strftime("%Y%m%d%H%M%S")}.db")
        @folder = folder
      end

      def call
        FileUtils.mkdir_p(@folder)
        verdict(@path, "source")
        copy
        verdict(@target, "copy")
        @target
      rescue
        FileUtils.rm_f(@target)
        raise
      end

      private

      def copy
        db = SQLite3::Database.new(@path)
        db.execute("VACUUM INTO ?", [@target])
      ensure
        db&.close
      end

      def verdict(path, what)
        db = SQLite3::Database.new(path, readonly: true)
        result = db.get_first_value("PRAGMA quick_check")
        raise SQLite3::CorruptException, "the #{what} of the home database fails the quick check: #{result}" unless result == "ok"
      ensure
        db&.close
      end
    end
  end
end
