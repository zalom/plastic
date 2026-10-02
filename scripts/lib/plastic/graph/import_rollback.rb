# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module Plastic
  module Graph
    # Preserves the source beside the store until import or recovery succeeds.
    class ImportRollback
      def initialize(root)
        @root = root
      end

      def call
        @saved = Dir.mktmpdir(".plastic-import-", File.dirname(@root))
        @original = File.join(@saved, File.basename(@root))
        FileUtils.cp_r(@root, @original)
        run { yield }
      ensure
        FileUtils.rm_rf(@saved) if @saved && !@retain
      end

      private

      def run
        yield
      rescue
        restore
        raise
      end

      def restore
        disconnect
        File.rename(@root, File.join(@saved, "failed-import")) if File.exist?(@root)
        File.rename(@original, @root)
      rescue => error
        @retain = true
        raise Invalid, "rollback failed; original store preserved at #{@original}: #{error.message}"
      end

      def disconnect
        pool = Database::ConnectionPool
        pool.disconnect(keep: pool.connections.keys.reject { |path| path.start_with?("#{@root}/") })
      end
    end
  end
end
