# frozen_string_literal: true

require "fileutils"
require_relative "target"
require_relative "writer"

module Plastic
  module Graph
    module Backup
      # Writes a complete backup folder with its row, or neither.
      class Publisher
        def initialize(target, now:, databases: nil, live: ->(_line) {}, **mode)
          @target = target
          @writer = Writer.new(target.root, target.slug, now:, copy: Copy.new(now:, databases:, live:), **mode)
        end

        # The row written, or nil when an automatic backup had nothing to do.
        def call
          row = @writer.call
          row && insert(row)
        rescue
          FileUtils.rm_rf(@target.folders.path(row.fetch(:name).split("/").last)) if row
          raise
        end

        private

        def insert(row)
          row = row.merge(session_id: @target.session)
          @target.local_db.transaction { |batch| batch.put(:backups, row, statement: :insert) }
          row
        end
      end
    end
  end
end
