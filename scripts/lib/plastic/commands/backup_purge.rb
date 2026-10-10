# frozen_string_literal: true

require_relative "../routine"
require_relative "backup_store"
require_relative "../graph/knowledge/backup/older_than"

module Plastic
  module Commands
    # Deletes backups of one registered store: all of them, those before a date, or those that failed.
    class BackupPurge < Routine
      include BackupStore

      writes :work

      def self.usage_line(tool = tool_name) = super.sub("[--older-than DATE] [--all] [--failed]", "(--older-than DATE | --all | --failed)")

      option :older_than, switch: "--older-than DATE", text: "delete the backups before this date or time"
      option :all, switch: "--all", default: false, text: "delete every backup of the store"
      option :failed, switch: "--failed", default: false, text: "delete every backup whose status is failed"
      option :dry_run, switch: "--dry-run", default: false, text: "list what would be deleted and delete nothing"

      workflow :code_preview_backup_purge do
        on :done, next: :noop
        on :continue, next: :code_backup_purge
      end
      workflow :code_backup_purge, next: :noop

      private

      def check_call
        one_of(%i[older_than all failed], give: "give --older-than DATE, --all or --failed", both: "--older-than, --all and --failed exclude each other")
        read_date
      end

      def read_date
        text = parsed[:older_than]
        as_usage(Graph::Knowledge::Backup::OlderThan::Unreadable) { Graph::Knowledge::Backup::OlderThan.parse(text) } if text
      end
    end
  end
end
