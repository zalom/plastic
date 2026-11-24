# frozen_string_literal: true

require_relative "../backup"
require_relative "../../../routine"
require_relative "../../../cli/one_store"
require_relative "../../../cli/asking_scope"

module Plastic
  module Commands
    module Store
      class Backup
        # Replaces the databases of one registered store with those of a done backup.
        class Restore < Routine
          include CLI::OneStore

          writes :work, :knowledge, :retrieval
          skips_daily_backup

          option :timestamp, switch: "--timestamp TS", text: "the backup to restore, by its folder name"
          option :latest, switch: "--latest", default: false, text: "restore the newest done backup that holds a database file"
          option :databases, switch: "--databases LIST", text: "the databases to restore, comma separated; all the backup holds when left out"
          option :dry_run, switch: "--dry-run", default: false, text: "list what would be replaced and change nothing"

          workflow :code_preview_backup_restore do
            on :done, next: :noop
            on :continue, next: :code_backup_restore
          end
          workflow :code_backup_restore, next: :noop

          private

          def check_call
            one_of(%i[timestamp latest], give: "give --timestamp TS or --latest", both: "--latest and --timestamp exclude each other")
            database_list
          end

          def new_scope = CLI::AskingScope.for(environment, slug: parsed[:project], output:)
        end
      end
    end
  end
end
