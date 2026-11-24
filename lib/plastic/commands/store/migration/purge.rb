# frozen_string_literal: true

require_relative "down"

module Plastic
  module Commands
    module Migration
      # Removes the rows one migration of a registered store kept in legacy.db, so a down can no longer undo it.
      class Purge < Routine
        include CLI::MigrationStore

        opens_no_store
        skips_daily_backup
        backs_up_first

        argument :version, label: "VERSION", text: "the migration whose kept rows go, by its version"

        workflow :code_migration_purge, next: :noop
      end
    end
  end
end
