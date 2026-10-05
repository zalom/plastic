# frozen_string_literal: true

require_relative "../routine"
require_relative "backup_store"

module Plastic
  module Commands
    # Replaces the databases of one registered store with those of a done backup.
    class BackupRestore < Routine
      include BackupStore

      option :timestamp, switch: "--timestamp TS", text: "the backup to restore, by its folder name"
      option :latest, switch: "--latest", default: false, text: "restore the newest backup that is done"
      option :databases, switch: "--databases LIST", text: "the databases to restore, comma separated; all the backup holds when left out"
      option :dry_run, switch: "--dry-run", default: false, text: "list what would be replaced and change nothing"

      workflow :code_preview_backup_restore do
        on :done, next: :noop
        on :continue, next: :code_backup_restore
      end
      workflow :code_backup_restore, next: :noop

      private

      def check_call
        raise CLI::Command::Usage, "give --timestamp TS or --latest" unless parsed[:timestamp] || parsed[:latest]
        raise CLI::Command::Usage, "--latest and --timestamp exclude each other" if parsed[:timestamp] && parsed[:latest]

        database_list
      end

      def keeps_routine_run? = !parsed[:dry_run]
    end
  end
end
