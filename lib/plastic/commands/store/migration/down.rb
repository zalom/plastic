# frozen_string_literal: true

require_relative "../../routine"
require_relative "../../cli/backup_store"

module Plastic
  module Commands
    # The commands that work on the migrations of one store.
    module Migration
      # Undoes the newest migration of one registered store from the rows it kept in legacy.db, after a backup.
      class Down < Routine
        include CLI::MigrationStore

        opens_no_store
        skips_daily_backup

        workflow :code_migration_down, next: :noop
      end
    end
  end
end
