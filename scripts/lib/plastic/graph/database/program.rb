# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"

module Plastic
  module Graph
    class Database
      # The sqlite3 program, which runs every script of a database: one
      # process per script, with each result set printed as JSON.
      class Program
        def initialize(search_path = ENV.fetch("PATH", ""))
          @search_path = search_path
        end

        # Fails before the first call when sqlite3 is not on the search path.
        def check
          found = @search_path.split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, "sqlite3")) }
          raise Error, "sqlite3 is not on PATH; install it, then call again" unless found
        end

        # The result sets of one script run on the file at `path`.
        def call(path, script)
          out, err, status = Open3.capture3("sqlite3", "-json", "-bail", folder(path), stdin_data: script)
          raise Error, "#{File.basename(path)}: #{err.strip}" unless status.success?

          Program.result_sets(out)
        end

        # Each set prints as one JSON array; a raw newline never occurs
        # inside a JSON string, so "]\n[" only separates two sets.
        def self.result_sets(out)
          text = out.strip
          text.empty? ? [] : JSON.parse("[#{text.gsub("]\n[", "],[")}]")
        end

        private

        # The database's path, with its folder made first.
        def folder(path)
          FileUtils.mkdir_p(File.dirname(path))
          path
        rescue SystemCallError => error
          raise Error, "#{File.basename(path)}: #{error.message}"
        end
      end
    end
  end
end
