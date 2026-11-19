# frozen_string_literal: true

require_relative "../migration"
require_relative "../../../code_workflow"
require_relative "../../../errors"
require_relative "../../../graph/migration/migration_purge"

module Plastic
  module Workflows
    module Code
      module Migration
        # Removes the rows one migration of a store kept in legacy.db and gives their space back to the disk.
        class Purge < CodeWorkflow
          clear_declarations
          summary "Removes the rows one migration of a store kept in legacy.db, so a down can no longer undo it."

          sets :moved

          step "remove the kept rows", done: ->(context) { !context.moved.nil? },
            changes: { databases: "The legacy tables of the migration go from legacy.db, and the ledger in plastic.db gets a purge row" } do |context|
            context[:moved] = Plastic::Graph::MigrationPurge.new(context.scope.plastic_home, context.store, context.now).call(context.version)
          rescue Plastic::Graph::MigrationPurge::Nothing => error
            raise Usage, error.message
          end

          read "say what was removed" do |context|
            context.print("purge: removed #{Migration.counted(context.moved)} from legacy.db")
            context.print("purge: migration #{context.version} of #{context.store} can no longer be undone")
          end

          outcome :done, offers: "plastic migration list --store %{store}", because: "the rows migration %{version} kept are gone from legacy.db"
        end
      end
    end
  end
end
