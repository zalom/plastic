# frozen_string_literal: true

require "fileutils"
require_relative "writer"

module Plastic
  module Graph
    module Knowledge
      class Backup
        # Writes a complete backup folder with its row, or neither.
        class Publisher
          def initialize(home_db, store_root, slug, now:, databases: nil, session: nil)
            @home_db = home_db
            @root = store_root
            @session = session
            @writer = Writer.new(store_root, slug, now:, databases:)
          end

          def call
            row = @writer.call
            insert(row)
          rescue
            FileUtils.rm_rf(Folders.new(@root).path(row.fetch(:name).split("/").last)) if row
            raise
          end

          private

          def insert(row)
            row = row.merge(session_id: @session)
            @home_db.transaction { |batch| batch.put(:backups, row, statement: :insert) }
            row
          end
        end
      end
    end
  end
end
