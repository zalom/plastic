# frozen_string_literal: true

require "fileutils"
require "yaml"
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
      # The two backups of one store on one day. The day of a backup is the
      # calendar day in the zone of the machine when it was taken, read from
      # its UTC time, so the days the clocks change count right. The first
      # call of the day copies the store with the reason "start of day",
      # changed or not. A session end on a day that has it copies the store
      # with the reason "end of day", unless the day's
      # end-of-day backup holds the store as it is, and once the copy is
      # written deletes the day's earlier end-of-day backups. Each backup
      # written is followed by the purge of the folders older than one day,
      # which keeps every backup of today, even on a 25-hour day. A
      # start-of-day backup that fails counts as tried for the rest of the
      # day, so a later call says nothing and the session end tries the
      # end-of-day backup. A backup that fails leaves no folder behind.
      class Day
        START = "start of day"
        FINISH = "end of day"
        FAILED_START = "failed-start-of-day.yml"

        def initialize(root, slug, now:, copy: Copy.new(now:))
          @root = root
          @slug = slug
          @now = now
          @copy = copy
          @folders = Folders.new(root)
        end

        # Takes the start-of-day backup when the day has none yet.
        def begin_day = (start unless sources.empty? || started?)

        # Takes the end-of-day backup, or the start-of-day one when the day has none yet.
        def end_session
          return if sources.empty?

          started? ? finish : start
        end

        private

        def sources = @copy.sources(@root)

        def started? = done_today(START).any? || failed_start_today?

        def start
          write(START)
        rescue
          record_failed_start
          raise
        end

        def failed_start_file = File.join(@folders.dir, FAILED_START)

        def record_failed_start
          FileUtils.mkdir_p(@folders.dir)
          File.write(failed_start_file, { "at" => Plastic.timestamp(@now) }.to_yaml)
        end

        def failed_start_today?
          file = failed_start_file
          File.file?(file) && today?(Plastic.local_day(YAML.safe_load_file(file).to_h["at"]))
        end

        def finish
          earlier = done_today(FINISH)
          return if holds_store?(earlier.last)

          earlier.each { |name| purger.remove(name) } if write(FINISH)
        end

        def holds_store?(name) = !name.nil? && @folders.report(name)["fingerprint"] == fingerprint

        def fingerprint = SourceCheck.new(sources.map { |name| File.join(@root, "#{name}.db") }).fingerprint

        # The backup row, or nil when another process took the folder name; only a written backup is followed by the purge.
        def write(reason)
          before = @folders.names
          Writer.new(@root, @slug, now: @now, copy: @copy, reason:).call&.tap { purger.sweep(now: @now, keep: @folders.names.select { |name| today?(day_of(name)) }) }
        rescue
          remove_failed(@folders.names - before)
          raise
        end

        def remove_failed(names) = names.select { |name| @folders.status(name) == "failed" }.each { |name| purger.remove(name) }

        def purger = Purger.new(@root, retention: Purger::DAILY_RETENTION)

        # The folders of the day that are done and record the reason, oldest first.
        def done_today(reason)
          @folders.names.select { |name| today?(day_of(name)) && @folders.status(name) == "done" && @folders.report(name)["reason"] == reason }
        end

        def today?(day) = day == @now.getlocal.strftime("%F")

        # The day in the taken_at time of the status file; a folder written before it was recorded reads its folder name.
        def day_of(name) = @folders.report(name)["taken_at"]&.then { |stamp| Plastic.local_day(stamp) } || FolderName.time(name).getlocal.strftime("%F")
      end
    end
  end
end
