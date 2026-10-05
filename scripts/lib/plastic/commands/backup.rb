# frozen_string_literal: true

require_relative "../routine"
require_relative "backup_store"

module Plastic
  module Commands
    # Copies one registered store's databases into a new backup folder.
    class Backup < Routine
      include BackupStore

      option :databases, switch: "--databases LIST", text: "the databases to copy, comma separated; all of them when left out"
      option :dry_run, switch: "--dry-run", default: false, text: "preview the backup without writing a folder"

      workflow :code_preview_backup do
        on :done, next: :noop
        on :continue, next: :code_backup
      end
      workflow :code_backup, next: :noop

      private

      def check_call = database_list

      def keeps_routine_run? = !parsed[:dry_run]
    end
  end
end
