# frozen_string_literal: true

require_relative "../backup"
require_relative "copy"
require_relative "folder_name"
require_relative "folders"
require_relative "purger"
require_relative "writer"

module Plastic
  module Graph
    module Backup
      # The automatic backup of one store: taken when the newest backup is
      # older than twelve hours, with the reason that asked for it. It never
      # raises, because a trigger must not stop the call that asked. A store with
      # no database file is missing and needs none. A store
      # that cannot be backed up answers :failed, and the call goes on. The
      # time is passed in. A backup that was taken is followed by the purge of the
      # folders older than three days, or one day under the daily backups, which
      # keeps the newest done backup and the newest backup of a migration.
      class Due
        WINDOW = 12 * 3600

        # :taken, :unchanged, :fresh, :missing or :failed, the backup row when one was written, and the reason when it failed.
        Result = Data.define(:status, :row, :reason)

        def initialize(home:, slug:, now:, retention: Purger::RETENTION)
          @root = File.join(home, "stores", slug)
          @slug = slug
          @now = now
          @retention = retention
        end

        def call(reason)
          return Result.new(:missing, nil, nil) if Copy.new(now: @now).sources(@root).empty?
          return Result.new(:fresh, nil, nil) unless stale?

          row = Writer.new(@root, @slug, now: @now, automatic: true, reason:).call
          purge if row
          Result.new(row ? :taken : :unchanged, row, nil)
        rescue => error
          Result.new(:failed, nil, error.message.lines.first.to_s.strip)
        end

        private

        def purge
          Purger.new(@root, retention: @retention).sweep(now: @now)
        end

        def stale?
          newest = Folders.new(@root).latest
          newest.nil? || (@now - FolderName.time(newest)) > WINDOW
        end
      end
    end
  end
end
