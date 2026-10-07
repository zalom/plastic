# frozen_string_literal: true

module Plastic
  module Graph
    class Database
      # The name a database file had before, such as home.db before local.db.
      # Moving it renames the file and its journal files, once, and only when
      # no file has the new name yet.
      class FormerName
        SUFFIXES = ["-journal", "-wal", "-shm", ""].freeze

        def initialize(path)
          @path = path
        end

        # The phrase the report prints for the rename, or nil when nothing moved.
        def move_to(target)
          return unless File.file?(@path) && !File.exist?(target)

          SUFFIXES.each { |suffix| move("#{@path}#{suffix}", "#{target}#{suffix}") }
          "#{File.basename(@path)} renamed to #{File.basename(target)}"
        end

        private

        def move(from, to) = File.exist?(from) && File.rename(from, to)
      end
    end
  end
end
