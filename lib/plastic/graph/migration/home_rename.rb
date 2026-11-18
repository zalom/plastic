# frozen_string_literal: true

require "sqlite3"

module Plastic
  module Graph
    # Renames the home database and its journal files while a second
    # connection holds the write lock, so no writer has the file open for
    # a write at the moment it moves. A file already at the new name is never replaced.
    class HomeRename
      # The new name is taken by another file.
      class Taken < StandardError; end

      SUFFIXES = ["-journal", "-wal", "-shm", ""].freeze

      def initialize(former, target, timeout: 5_000)
        @former = former
        @target = target
        @timeout = timeout
      end

      def call
        raise Taken, "#{File.basename(@target)} already exists" if File.exist?(@target)

        SQLite3::Database.new(@former) do |db|
          db.busy_timeout = @timeout
          db.execute("BEGIN IMMEDIATE")
          move
          db.execute("ROLLBACK")
        end
      end

      private

      def move = SUFFIXES.map { |suffix| ["#{@former}#{suffix}", "#{@target}#{suffix}"] }.select { |from, _to| File.exist?(from) }.each { |from, to| File.rename(from, to) }
    end
  end
end
