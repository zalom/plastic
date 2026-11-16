# frozen_string_literal: true

require "time"
require_relative "check"
require_relative "../graph/backup/folders"
require_relative "../graph/backup/folder_name"

module Plastic
  module Doctor
    # One store's newest backup as the doctor prints it: when it was taken,
    # how old it is, and whether its integrity check passed. A backup folder
    # is marked done only after every database passed the quick check, so any
    # other status is a finding. A store with no backup yet is no finding.
    class StoreBackups
      def initialize(store_root, slug, now:)
        @folders = Graph::Backup::Folders.new(store_root)
        @slug = slug
        @now = now
      end

      def check
        newest = @folders.latest
        label = "backups #{@slug}:"
        return Check.ok(label, "no backup yet") unless newest

        status = @folders.status(newest)
        return Check.ok(label, described(newest)) if status == "done"

        Check.finding(label, "newest backup #{newest} is #{status}; its integrity check did not pass", "plastic backup --store #{@slug}")
      end

      private

      def described(name)
        taken = Graph::Backup::FolderName.time(name)
        "newest #{taken.utc.iso8601}, #{((@now - taken) / 3600).floor} hours old, integrity passed"
      end
    end
  end
end
