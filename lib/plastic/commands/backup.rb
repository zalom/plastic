# frozen_string_literal: true

require_relative "../routine"
require_relative "backup_store"
require_relative "streaming_scope"

module Plastic
  module Commands
    # Copies one registered store's databases into a new backup folder.
    class Backup < Routine
      include BackupStore

      writes :work

      option :databases, switch: "--databases LIST", text: "the databases to copy, comma separated; all of them when left out"
      option :live, switch: "--live", default: false, text: "print each line of the backup log as it is written"
      option :dry_run, switch: "--dry-run", default: false, text: "preview the backup without writing a folder"

      workflow :code_preview_backup do
        on :done, next: :noop
        on :continue, next: :code_backup
      end
      workflow :code_backup, next: :noop

      private

      def check_call = database_list

      def scope = @scope ||= StreamingScope.for(environment, slug: parsed[:store], output: (parsed[:live] ? output : nil))
    end
  end
end
