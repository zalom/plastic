# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../../file_system"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # Preserves the source beside the store until import or recovery succeeds.
        class ImportRollback
          def initialize(root, files: FileSystem.new)
            @root = root
            @files = files
            @saved = nil
            @retain = false
          end

          def call
            @saved = Dir.mktmpdir(".plastic-import-", File.dirname(@root))
            @files.copy_tree(@root, original)
            restore_unless_finished { yield }
          ensure
            FileUtils.rm_rf(@saved) if @saved && !@retain
          end

          private

          def original = File.join(@saved, File.basename(@root))

          def restore_unless_finished
            finished = false
            yield.tap { finished = true }
          ensure
            restore unless finished
          end

          def restore
            put_back
          rescue => error
            @retain = true
            raise Invalid, "rollback failed; original store preserved at #{original}: #{error.message}"
          end

          def put_back
            set_aside
            @files.rename(original, @root)
            remove_created_databases
          end

          # A database this process made goes with the failed import; a database the store held before stays.
          def remove_created_databases
            made = Database::ConnectionPool.created.select { |path| path.start_with?("#{@root}/") }
            made.flat_map { |path| ["", "-wal", "-shm", "-journal"].map { |suffix| "#{path}#{suffix}" } }.uniq.select { |path| File.file?(path) }.each { |path| File.delete(path) }
          end

          def set_aside
            disconnect
            @files.rename(@root, File.join(@saved, "failed-import")) if File.exist?(@root)
          end

          def disconnect
            live = Database::ConnectionPool.connections.keys
            Database::ConnectionPool.disconnect(keep: live.reject { |path| path.start_with?("#{@root}/") })
          end
        end
      end
    end
  end
end
