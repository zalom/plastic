# frozen_string_literal: true

require "json"
require_relative "../migration"
require_relative "../../../code_workflow"
require_relative "../../../graph/database"
require_relative "../../../graph/migration/migration_ledger"
require_relative "../../../graph/schema/migration_list"

module Plastic
  module Workflows
    module Code
      module Migration
        # Prints the ledger rows of one store and what a down would undo now, from the ledger in plastic.db alone.
        class List < CodeWorkflow
          clear_declarations
          summary "Prints the ledger rows of one store and what a down would undo now."

          def self.ledger(context) = Plastic::Graph::MigrationLedger.new(Plastic::Graph::Database.open_local(context.scope.plastic_home).fetch(:local), context.now)

          def self.event(row) = row.values_at("at", "event", "version").push(Migration.counted(JSON.parse(row.fetch("moved")))).join("  ")

          def self.down_line(ledger, store)
            version = Plastic::Graph::MIGRATIONS.versions(:store).last
            moved = ledger.undoable(store, version)
            moved ? "down: would undo migration #{version} and put back #{Migration.counted(moved)}" : "down: nothing to undo"
          end

          read "print the ledger" do |context|
            ledger = ledger(context)
            store = context.store
            rows = ledger.of(store)
            next context.print("no migration of #{store} is in the ledger") if rows.empty?

            rows.each { |row| context.print(event(row)) }
            context.print(down_line(ledger, store))
          end

          outcome :done, offers: nil, because: "the list only reads; a down is the person's call"
        end
      end
    end
  end
end
