# frozen_string_literal: true

require_relative "../backup"
require_relative "copy"
require_relative "folder_name"
require_relative "folders"
require_relative "purger"
require_relative "source_check"
require_relative "writer"

module Plastic
  module Graph
    module Backup
      # The two backups of one store on one day. The day is the calendar day
      # of the clock, in the clock's own offset. The first call of the day
      # copies the store with the reason "start of day", changed or not. A
      # session end on a day that has it copies the store with the reason
      # "end of day", unless the day's end-of-day backup holds the store as it
      # is, and then deletes the day's earlier end-of-day backups. Each backup
      # taken is followed by the purge of the folders older than one day.
      class Day
        START = "start of day"
        FINISH = "end of day"

        def initialize(root, slug, now:)
          @root = root
          @slug = slug
          @now = now
          @folders = Folders.new(root)
        end

        # Takes the start-of-day backup when the day has none yet.
        def begin_day = (write(START) unless sources.empty? || started?)

        # Takes the end-of-day backup, or the start-of-day one when the day has none yet.
        def end_session
          return if sources.empty?

          started? ? finish : write(START)
        end

        private

        def sources = Copy.new(now: @now).sources(@root)

        def started? = done_today(START).any?

        def finish
          earlier = done_today(FINISH)
          return if holds_store?(earlier.last)

          write(FINISH)
          earlier.each { |name| purger.remove(name) }
        end

        def holds_store?(name) = !name.nil? && @folders.report(name)["fingerprint"] == fingerprint

        def fingerprint = SourceCheck.new(sources.map { |name| File.join(@root, "#{name}.db") }).fingerprint

        def write(reason)
          Writer.new(@root, @slug, now: @now, reason:).call
          purger.sweep(now: @now)
        end

        def purger = Purger.new(@root, retention: Purger::DAILY_RETENTION)

        # The folders of the day that are done and record the reason, oldest first.
        def done_today(reason)
          @folders.names.select { |name| today?(name) && @folders.status(name) == "done" && @folders.report(name)["reason"] == reason }
        end

        def today?(name) = FolderName.time(name).getlocal(@now.utc_offset).strftime("%F") == @now.strftime("%F")
      end
    end
  end
end
