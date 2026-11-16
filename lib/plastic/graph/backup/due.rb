# frozen_string_literal: true

require_relative "../backup"
require_relative "folder_name"
require_relative "folders"
require_relative "purger"
require_relative "writer"

module Plastic
  module Graph
    module Backup
      # The automatic backup of one store: taken when the newest backup is
      # older than twelve hours, with the reason that asked for it. It never
      # raises, because a trigger must not stop the call that asked: a store
      # that cannot be backed up answers :failed, and the call goes on. The
      # time is passed in. A backup that was taken is followed by the purge of the
      # folders older than three days, which keeps the newest done backup and the
      # newest backup of a migration.
      class Due
        WINDOW = 12 * 3600

        # :taken, :unchanged, :fresh, :missing or :failed, the backup row when one was written, and the reason when it failed.
        Result = Data.define(:status, :row, :reason)

        def initialize(home:, slug:, now:)
          @home = home
          @root = File.join(home, "stores", slug)
          @slug = slug
          @now = now
        end

        def call(reason)
          return Result.new(:missing, nil, nil) unless File.directory?(@root)
          return Result.new(:fresh, nil, nil) unless stale?

          row = Writer.new(@root, @slug, now: @now, automatic: true, reason:).call
          purge if row
          Result.new(row ? :taken : :unchanged, row, nil)
        rescue => error
          Result.new(:failed, nil, error.message.lines.first.to_s.strip)
        end

        private

        def purge
          purger = Purger.new(@root)
          (purger.expired(now: @now) - [newest_done]).each { |name| purger.remove(name) }
        end

        def newest_done
          folders = Folders.new(@root)
          folders.names.reverse.find { |name| folders.status(name) == "done" }
        end

        def stale?
          newest = Folders.new(@root).latest
          newest.nil? || (@now - FolderName.time(newest)) > WINDOW
        end
      end
    end
  end
end
