# frozen_string_literal: true

require "fileutils"
require "sqlite3"

module Plastic
  module Graph
    # The copy of the home database taken before it migrates: the source is
    # checked, VACUUM INTO writes <home>/backups/<file name>-<UTC timestamp>.db,
    # and the copy is checked too. It raises when any step fails, and a failed
    # copy is removed. A copy already at the target is never replaced.
    class HomeCopy
      # The copy's name is taken by an earlier copy.
      class Exists < StandardError; end

      def initialize(path, folder, now)
        @path = path
        @target = File.join(folder, "#{File.basename(path, ".db")}-#{now.utc.strftime("%Y%m%d%H%M%S")}.db")
        @folder = folder
      end

      def call
        raise Exists, "#{File.basename(@target)} already exists" if File.exist?(@target)

        FileUtils.mkdir_p(@folder)
        verdict(@path, "source")
        made
      end

      private

      def made
        copy
        verdict(@target, "copy")
        @target
      rescue
        FileUtils.rm_f(@target)
        raise
      end

      def copy
        SQLite3::Database.new(@path) { |db| db.execute("VACUUM INTO ?", [@target]) }
      end

      def verdict(path, what)
        result = SQLite3::Database.open(path, readonly: true) { |db| db.get_first_value("PRAGMA quick_check") }
        raise SQLite3::CorruptException, "the #{what} of the home database fails the quick check: #{result}" unless result == "ok"
      end
    end
  end
end
