# frozen_string_literal: true

require "yaml"
require_relative "../backup"
require_relative "folder_name"
require_relative "folders"

module Plastic
  module Graph
    module Backup
      # Which backup folders of one store belong to today, in the zone the day is read in. A folder
      # whose name is not a real time and that records no taken_at belongs to no day.
      class DayReader
        # A file under backups/ holds a time that is no time; the message names the file and the value.
        class Unreadable < StandardError; end

        attr_reader :folders

        def initialize(folders, now:, zone:)
          @folders = folders
          @now = now
          @zone = zone
        end

        # The folders of the day that are done and record the reason, oldest first.
        def done(reason)
          today_names.select { |name| folders.status(name) == "done" && folders.report(name)["reason"] == reason }
        end

        def today_names = folders.names.select { |name| today?(day_of(name)) }

        def today?(day) = day == @now.getlocal(@zone).strftime("%F")

        def read_day(file, stamp)
          Plastic.local_day(stamp, @zone)
        rescue ArgumentError
          raise Unreadable, "#{File.join(Folders::NAME, file)} holds #{stamp}, which is not a time; fix or delete the file"
        end

        private

        # The day in the taken_at time of the status file; a folder written before it was recorded reads its folder name.
        def day_of(name)
          folders.report(name)["taken_at"]&.then { |stamp| read_day("#{name}/status.yml", stamp) } || FolderName.day(name, @zone)
        end
      end
    end
  end
end
