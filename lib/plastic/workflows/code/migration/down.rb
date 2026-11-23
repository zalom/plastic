# frozen_string_literal: true

require_relative "../migration"
require_relative "../../../code_workflow"
require_relative "../../../errors"
require_relative "../../../graph/migration/migration_down"

module Plastic
  module Workflows
    module Code
      module Migration
        # Puts back the rows the newest migration of one store kept in legacy.db and removes its version, after a backup.
        class Down < CodeWorkflow
          clear_declarations
          summary "Puts back the rows the newest migration of one store kept in legacy.db and removes its version, after a backup."

          sets :refusal, :version, :moved, :built, :removed, :backup, :ledger_gap

          # How a down that fails after the check stops the call: a failed backup is exit 1, a refusal exit 3.
          STOPS = { Plastic::Graph::MigrationDown::BackupFailed => Failed, Plastic::Graph::MigrationDown::Refused => Refused,
                    Plastic::Graph::LegacyTable::Changed => Refused }.freeze

          def self.down(context) = Plastic::Graph::MigrationDown.new(context.scope.plastic_home, context.store, context.now)

          def self.undo(context)
            down(context).call.to_h.each { |name, value| context[name] = value }
          rescue *STOPS.keys => error
            raise STOPS.fetch(error.class), error.message
          end

          read "check the store can go down" do |context|
            context[:refusal] = down(context).refusal
          end

          gate "%{refusal}", stops: :refusal,
            words: "the store is not current, its newest migration kept nothing, or a row it kept changed since",
            pass: ->(context) { context.refusal.nil? }

          step "put the kept rows back", done: ->(context) { !context.version.nil? },
            changes: { databases: "The rows the newest migration kept in legacy.db go back into the store, and its version goes", backups: "A backup of the store is written first" } do |context|
            undo(context)
          end

          read "say what was put back" do |context|
            context.print("down: put back #{Migration.counted(context.moved)} from legacy.db")
            context.print("down: #{context.store} no longer records migration #{context.version}")
            context.print("down: built #{Migration.counted(context.built)} from the current documents")
            context.print("down: removed #{context.removed} needs #{(context.removed == 1) ? "link" : "links"} that the migration wrote") if context.removed
            context.warn("down: #{context.store} no longer records migration #{context.version}, but the ledger in plastic.db has no down row for it (#{context.ledger_gap})") if context.ledger_gap
          end

          outcome :done, offers: "plastic migration list --store %{store}",
            because: "%{store} no longer records migration %{version}, and plastic update migrates it up again; a down undoes one store, so an older release still refuses plastic.db and the other stores"
        end
      end
    end
  end
end
