# frozen_string_literal: true

require "find"
require "fileutils"
require "sqlite3"

module Plastic
  module Graph
    module Knowledge
      class Sync
        class Preview
          # A disposable twin of one store folder: each database is taken with
          # VACUUM INTO, every other file is a hard link to the original, or a
          # copy where a link is impossible. The sync code only ever replaces
          # a file with a new one, so a link never changes the original.
          class Mirror
            DATABASE = /\.db\z/
            SIDECAR = /\.db-(?:wal|shm|journal)\z/

            def initialize(source, target)
              @source = source
              @target = target
            end

            def call
              FileUtils.mkdir_p(@target)
              Find.find(@source) { |path| place(path) unless path == @source } if File.directory?(@source)
            end

            private

            def place(path)
              target = File.join(@target, path.delete_prefix("#{@source}/"))
              return FileUtils.mkdir_p(target) if File.directory?(path)

              if path.match?(DATABASE) then vacuum(path, target)
              elsif !path.match?(SIDECAR) then link(path, target)
              end
            end

            def vacuum(path, target)
              database = SQLite3::Database.new(path, readonly: true)
              database.execute("VACUUM INTO ?", [target])
            ensure
              database&.close
            end

            def link(path, target)
              File.link(path, target)
            rescue SystemCallError
              FileUtils.cp(path, target)
            end
          end
        end
      end
    end
  end
end
