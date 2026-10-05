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
            run { yield }
          ensure
            FileUtils.rm_rf(@saved) if @saved && !@retain
          end

          private

          def original = File.join(@saved, File.basename(@root))

          def run
            yield
          rescue
            restore
            raise
          end

          def restore
            set_aside
            @files.rename(original, @root)
          rescue => error
            @retain = true
            raise Invalid, "rollback failed; original store preserved at #{original}: #{error.message}"
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
