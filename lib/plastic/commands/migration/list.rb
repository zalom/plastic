# frozen_string_literal: true

require_relative "down"

module Plastic
  module Commands
    module Migration
      # Prints the ledger rows of one registered store and what a down would undo now. It changes nothing.
      class List < Routine
        include CLI::BackupStore

        opens_no_store
        skips_daily_backup

        workflow :code_migration_list, next: :noop
      end
    end
  end
end
