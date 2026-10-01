# frozen_string_literal: true

require "json"
require_relative "session"

module Plastic
  module Graph
    class Database
      # The sqlite3 program, which runs every script of a database through
      # the file's one Session in the ConnectionPool, with each result set
      # printed as JSON.
      class Program
        def initialize(search_path = ENV.fetch("PATH", ""), pool: ConnectionPool)
          @search_path = search_path
          @pool = pool
        end

        # Fails before the first call when sqlite3 is not on the search path.
        def check
          found = @search_path.split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, "sqlite3")) }
          raise Error, "sqlite3 is not on PATH; install it, then call again" unless found
        end

        # The result sets of one script run on the file at `path`.
        def call(path, script) = Program.result_sets(@pool.for(path).call(script))

        # Ends every session, as a test does after each test.
        def self.disconnect = ConnectionPool.disconnect

        # Each set prints as one JSON array; a raw newline never occurs
        # inside a JSON string, so "]\n[" only separates two sets.
        def self.result_sets(out)
          text = out.strip
          text.empty? ? [] : JSON.parse("[#{text.gsub("]\n[", "],[")}]")
        end
      end
    end
  end
end
