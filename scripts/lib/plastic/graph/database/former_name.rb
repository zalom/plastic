# frozen_string_literal: true

module Plastic
  module Graph
    class Database
      # The name a database file had before, such as home.db before local.db.
      # The first move renames the file and its journal files, and only when
      # no file has the new name yet. Later moves do nothing.
      class FormerName
        SUFFIXES = ["-journal", "-wal", "-shm", ""].freeze

        # The phrase the report prints for the rename, or nil when nothing moved.
        attr_reader :said

        def initialize(path)
          @path = path
          @pending = true
          @said = nil
        end

        def move_to(target)
          return @said unless @pending

          @pending = false
          @said = rename(target)
        end

        private

        def rename(target)
          return unless File.file?(@path) && !File.exist?(target)

          moves(target).each { |from, to| File.rename(from, to) }
          "#{File.basename(@path)} renamed to #{File.basename(target)}"
        end

        def moves(target) = SUFFIXES.map { |suffix| ["#{@path}#{suffix}", "#{target}#{suffix}"] }.select { |from, _to| File.exist?(from) }
      end
    end
  end
end
