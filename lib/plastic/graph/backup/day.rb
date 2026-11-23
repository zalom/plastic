# frozen_string_literal: true

require "fileutils"
require "yaml"
require_relative "../backup"
require_relative "copy"
require_relative "day_reader"
require_relative "folder_name"
require_relative "folders"
require_relative "purger"
require_relative "site"
require_relative "source_check"
require_relative "writer"

module Plastic
  module Graph
    module Backup
      # The two backups of one store on one day. The day of a backup is the
      # calendar day in the zone it is read in, an offset such as +01:00 or
      # else the zone of the machine, read from its UTC time, so the days the
      # clocks change count right. The first
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

        Unreadable = DayReader::Unreadable

        def initialize(root, slug, now:, copy: Copy.new(now:), zone: nil)
          @site = Site.new(root, slug)
          @now = now
          @copy = copy
          @days = DayReader.new(@site.folders, now:, zone:)
        end

        # Takes the start-of-day backup when the day has none yet.
        def begin_day = (start unless sources.empty? || started?)

        # Takes the end-of-day backup, or the start-of-day one when the day has none yet.
        def end_session
          return if sources.empty?

          started? ? finish : start
        end

        private

        def folders = @days.folders

        def sources = @copy.sources(@site.root)

        def started? = @days.done(START).any? || failed_start_today?

        def start
          write(START)
        rescue
          record_failed_start
          raise
        end

        def failed_start_file = File.join(folders.dir, FAILED_START)

        def record_failed_start
          FileUtils.mkdir_p(folders.dir)
          File.write(failed_start_file, { "at" => Plastic.timestamp(@now) }.to_yaml)
        end

        def failed_start_today?
          file = failed_start_file
          File.file?(file) && @days.today?(@days.read_day(FAILED_START, YAML.safe_load_file(file).to_h["at"]))
        end

        def finish
          earlier = @days.done(FINISH)
          newest = earlier.last
          return if newest && folders.report(newest)["fingerprint"] == fingerprint

          write(FINISH) && earlier.each { |name| purger.remove(name) }
        end

        def fingerprint = SourceCheck.new(sources.map { |name| File.join(@site.root, "#{name}.db") }).fingerprint

        # The backup row, or nil when another process took the folder name; only a written backup is followed by the purge.
        def write(reason)
          before = folders.names
          Writer.new(@site.root, @site.slug, now: @now, copy: @copy, reason:).call&.tap { purger.sweep(now: @now, keep: @days.today_names) }
        rescue
          remove_failed(before)
          raise
        end

        def remove_failed(before) = (folders.names - before).select { |name| folders.status(name) == "failed" }.each { |name| purger.remove(name) }

        def purger = Purger.new(@site.root, retention: Purger::DAILY_RETENTION)
      end
    end
  end
end
