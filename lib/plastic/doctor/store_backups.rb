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
        failed = failed_check
        return Check.finding(label, failed, "plastic store backup --project #{@slug}") if failed

        return Check.ok(label, "no backup yet") unless newest

        status = @folders.status(newest)
        return Check.ok(label, described(newest)) if status == "done"

        Check.finding(label, "newest backup #{newest} is #{status}; its integrity check did not pass", "plastic store backup --project #{@slug}")
      end

      private

      def failed_check
        file, at, reason, verdict = @folders.last_check.values_at("file", "at", "reason", "verdict")
        "the live check of #{file} failed at #{Plastic.local(at)}: #{reason}" if verdict == "failed"
      end

      def live_check
        at, verdict = @folders.last_check.values_at("at", "verdict")
        ", live check #{Plastic.local(at)} #{verdict}" if verdict
      end

      def described(name)
        taken = Graph::Backup::FolderName.time(name)
        "newest #{Plastic.local(Plastic.timestamp(taken))}, #{((@now - taken) / 3600).floor} hours old, integrity passed#{live_check}"
      end
    end
  end
end
