# frozen_string_literal: true

require_relative "../backup"
require_relative "folder_name"
require_relative "folders"
require_relative "writer"

module Plastic
  module Graph
    module Backup
      # The automatic backup of one store: taken when the newest backup is
      # older than twelve hours, with the reason that asked for it. It never
      # raises, because a trigger must not stop the call that asked: a store
      # that cannot be backed up answers :failed, and the call goes on. The
      # time is passed in.
      class Due
        WINDOW = 12 * 3600

        # :taken, :unchanged, :fresh, :missing or :failed, and the backup row when one was written.
        Result = Data.define(:status, :row)

        def initialize(home:, slug:, now:)
          @root = File.join(home, "stores", slug)
          @slug = slug
          @now = now
        end

        def call(reason)
          return Result.new(:missing, nil) unless File.directory?(@root)
          return Result.new(:fresh, nil) unless stale?

          row = Writer.new(@root, @slug, now: @now, automatic: true, reason:).call
          Result.new(row ? :taken : :unchanged, row)
        rescue => _error
          Result.new(:failed, nil)
        end

        private

        def stale?
          newest = Folders.new(@root).latest
          newest.nil? || (@now - FolderName.time(newest)) > WINDOW
        end
      end
    end
  end
end
