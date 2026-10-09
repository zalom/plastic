# frozen_string_literal: true

require_relative "../routine"
require_relative "backup_store"
require_relative "asking_scope"

module Plastic
  module Commands
    # Replaces the databases of one registered store with those of a done backup.
    class BackupRestore < Routine
      include BackupStore

      writes :work

      option :timestamp, switch: "--timestamp TS", text: "the backup to restore, by its folder name"
      option :latest, switch: "--latest", default: false, text: "restore the newest backup that is done"
      option :databases, switch: "--databases LIST", text: "the databases to restore, comma separated; all the backup holds when left out"
      option :dry_run, switch: "--dry-run", default: false, text: "list what would be replaced and change nothing"

      workflow :code_preview_backup_restore do
        on :done, next: :noop
        on :continue, next: :code_backup_restore
      end
      workflow :code_backup_restore, next: :code_ask_restore_sync
      workflow :code_ask_restore_sync do
        on :sync_down, next: :code_sync_down
        on :sync_up, next: :code_sync_up
        on :kept, next: :noop
        on :done, next: :noop
      end
      workflow :code_sync_down, next: :noop
      workflow :code_sync_up, next: :noop

      private

      def check_call
        one_of(%i[timestamp latest], give: "give --timestamp TS or --latest", both: "--latest and --timestamp exclude each other")
        database_list
      end

      def scope = @scope ||= AskingScope.for(environment, slug: parsed[:store], output:)
    end
  end
end
