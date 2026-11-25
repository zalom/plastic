# frozen_string_literal: true

require "find"
require "fileutils"
require "sqlite3"
require_relative "../../../backup/folders"

module Plastic
  module Graph
    module Knowledge
      class Sync
        class Preview
          # Copies a store folder into a twin: hard links for files, vacuumed copies for databases.
          class Mirror
            DATABASE = /\.db\z/
            BACKUPS = Backup::Folders::NAME
            SIDECAR = /\.db-(?:wal|shm|journal)\z/

            def initialize(source, target)
              @source = source
              @target = target
            end

            def call
              FileUtils.mkdir_p(@target)
              Find.find(@source) { |path| visit(path) } if File.directory?(@source)
            end

            private

            def visit(path)
              return if path == @source
              return Find.prune if path == File.join(@source, BACKUPS)

              place(path)
            end

            def place(path)
              return FileUtils.mkdir_p(mirrored(path)) if File.directory?(path)

              if path.match?(DATABASE) then vacuum(path)
              elsif !path.match?(SIDECAR) then link(path)
              end
            end

            def mirrored(path) = File.join(@target, path.delete_prefix("#{@source}/"))

            def vacuum(path)
              SQLite3::Database.new(path, readonly: true) { |database| database.execute("VACUUM INTO ?", [mirrored(path)]) }
            end

            def link(path)
              target = mirrored(path)
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
