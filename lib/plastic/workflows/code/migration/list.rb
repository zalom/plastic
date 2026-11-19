# frozen_string_literal: true

require "json"
require_relative "../migration"
require_relative "../../../code_workflow"
require_relative "../../../graph/database"
require_relative "../../../graph/migration/legacy_store"
require_relative "../../../graph/migration/migration_down"
require_relative "../../../graph/migration/migration_ledger"
require_relative "../../../graph/schema/state"

module Plastic
  module Workflows
    module Code
      module Migration
        # Prints what the store itself says: the newest version it records, the rows its legacy.db holds and what a down
        # would undo now. The ledger rows in plastic.db follow as its history, never as the truth.
        class List < CodeWorkflow
          clear_declarations
          summary "Prints the version of one store, the rows its legacy.db holds, its ledger rows and what a down would undo now."

          def self.ledger(context) = Plastic::Graph::MigrationLedger.new(Plastic::Graph::Database.open_local(context.scope.plastic_home).fetch(:local), context.now)

          def self.event(row) = row.values_at("at", "event", "version").push(Migration.counted(JSON.parse(row.fetch("moved")))).join("  ")

          def self.store(context) = Plastic::Graph::LegacyStore.new(context.scope.plastic_home, context.store)

          def self.version_line(context)
            number = Plastic::Graph::SchemaState.of_file(store(context).knowledge_file, :store).number
            "store: #{context.store} is at migration #{number}"
          end

          def self.legacy_lines(kept, slug)
            return ["legacy: #{slug} keeps no rows in legacy.db"] if kept.empty?

            kept.map { |version, moved| "legacy: migration #{version} keeps #{Migration.counted(moved)}" }
          end

          def self.history_lines(context)
            rows = ledger(context).of(context.store)
            rows.empty? ? ["no migration of #{context.store} is in the ledger"] : rows.map { |row| event(row) }
          end

          def self.down_line(context, kept)
            down = Plastic::Graph::MigrationDown.new(context.scope.plastic_home, context.store, context.now)
            refusal = down.refusal
            refusal ? "down: #{refusal}" : "down: would undo migration #{down.version} and put back #{Migration.counted(kept.fetch(down.version))}"
          end

          def self.kept(context)
            legacy = store(context)
            legacy.kept
          ensure
            legacy.release
          end

          read "print what the store holds and the ledger" do |context|
            kept = kept(context)
            [version_line(context), *legacy_lines(kept, context.store), *history_lines(context), down_line(context, kept)].each { |line| context.print(line) }
          end

          outcome :done, offers: nil, because: "the list only reads; a down is the person's call"
        end
      end
    end
  end
end
