# frozen_string_literal: true

require_relative "../backup"

module Plastic
  module Graph
    module Knowledge
      class Backup
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
          def self.before?(name, limit) = limit ? time(name) < limit : true

          # The moment a folder name stands for, in UTC.
          def self.time(name) = Time.utc(name[0, 4], name[4, 2], name[6, 2], name[8, 2], name[10, 2], name[12, 2])
        end
      end
    end
  end
end
