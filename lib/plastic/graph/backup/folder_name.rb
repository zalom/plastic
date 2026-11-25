# frozen_string_literal: true

module Plastic
  module Graph
    module Backup
      # The name of one backup folder: fourteen UTC digits of the time the
      # backup started, and a suffix when that name is already taken.
      module FolderName
        PATTERN = /\A\d{14}(?:-\d+)?\z/

        def self.timestamp(time) = time.getutc.strftime("%Y%m%d%H%M%S")

        def self.for(backups_dir, time)
          base = timestamp(time)
          return base unless File.exist?(File.join(backups_dir, base))

          (1..).lazy.map { |number| "#{base}-#{number}" }.find { |name| !File.exist?(File.join(backups_dir, name)) }
        end

        # Whether the folder is strictly before the limit; no limit means every folder is.
        def self.before?(name, limit) = limit ? readable?(name) && time(name) < limit : true

        # Whether the digits of the name make a real time; a name that does not has no age to judge.
        # Ruby rolls 20200231000000 over to 2 March, so the time must format back to the name.
        def self.readable?(name)
          timestamp(time(name)) == name[0, 14]
        rescue ArgumentError
          false
        end

        # The local start time of a folder as text, or unknown when its name is not a real time.
        def self.started(name) = readable?(name) ? time(name).localtime.strftime("%Y-%m-%d %H:%M:%S") : "unknown"

        # The local day a folder name stands for, or none when the name is not a real time.
        def self.day(name, zone) = (time(name).getlocal(zone).strftime("%F") if readable?(name))

        # The moment a folder name stands for, in UTC.
        def self.time(name) = Time.utc(name[0, 4], name[4, 2], name[6, 2], name[8, 2], name[10, 2], name[12, 2])
      end
    end
  end
end
