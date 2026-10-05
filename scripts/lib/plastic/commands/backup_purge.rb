# frozen_string_literal: true

require_relative "../routine"
require_relative "backup_store"
require_relative "../graph/knowledge/backup/older_than"

module Plastic
  module Commands
    # Deletes backups of one registered store: all of them, or those before a date.
    class BackupPurge < Routine
      include BackupStore

      option :older_than, switch: "--older-than DATE", text: "delete the backups before this date or time"
      option :all, switch: "--all", default: false, text: "delete every backup of the store"
      option :dry_run, switch: "--dry-run", default: false, text: "list what would be deleted and delete nothing"

      workflow :code_preview_backup_purge do
        on :done, next: :noop
        on :continue, next: :code_backup_purge
      end
      workflow :code_backup_purge, next: :noop

      private

      def check_call
        raise CLI::Command::Usage, "give --older-than DATE or --all" unless parsed[:older_than] || parsed[:all]
        raise CLI::Command::Usage, "--all and --older-than exclude each other" if parsed[:older_than] && parsed[:all]

        parsed[:older_than] && read_date
      end

      def read_date
        Graph::Knowledge::Backup::OlderThan.parse(parsed[:older_than])
      rescue Graph::Knowledge::Backup::OlderThan::Unreadable => error
        raise CLI::Command::Usage, error.message
      end

      def keeps_routine_run? = !parsed[:dry_run]
    end
  end
end
