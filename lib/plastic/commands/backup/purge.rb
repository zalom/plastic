# frozen_string_literal: true

require_relative "../backup"
require_relative "../../routine"
require_relative "../../cli/backup_store"
require_relative "../../graph/backup/older_than"

module Plastic
  module Commands
    class Backup
      # Deletes backups of one registered store: all of them, those before a date, those that failed, or those a stopped run left in progress.
      class Purge < Routine
        include CLI::BackupStore

        writes :work
        changes(work: KEPT_RUN_WORDS)

        def self.usage_line(tool = tool_name) = super.sub("[--older-than DATE] [--all] [--failed] [--interrupted]", "(--older-than DATE | --all | --failed | --interrupted)")

        option :older_than, switch: "--older-than DATE", text: "delete the backups before this date or time"
        option :all, switch: "--all", default: false, text: "delete every backup of the store"
        option :failed, switch: "--failed", default: false, text: "delete every backup whose status is failed"
        option :interrupted, switch: "--interrupted", default: false, text: "delete every backup in progress or with no status recorded for over five minutes, whether its run stopped or is only slow"
        option :dry_run, switch: "--dry-run", default: false, text: "list what would be deleted and delete nothing"

        workflow :code_preview_backup_purge do
          on :done, next: :noop
          on :continue, next: :code_backup_purge
        end
        workflow :code_backup_purge, next: :noop

        private

        def check_call
          one_of(%i[older_than all failed interrupted], give: "give --older-than DATE, --all, --failed or --interrupted", both: "--older-than, --all, --failed and --interrupted exclude each other")
          read_date
        end

        def read_date
          text = parsed[:older_than]
          as_usage(Plastic::Graph::Backup::OlderThan::Unreadable) { Plastic::Graph::Backup::OlderThan.parse(text) } if text
        end
      end
    end
  end
end
