# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../errors"
require_relative "../../../graph/migration/migration_down"

module Plastic
  module Workflows
    module Code
      # The workflows of the commands that work on the migrations of one store.
      module Migration
        # Puts back the rows the newest migration of one store kept in legacy.db and removes its version, after a backup.
        class Down < CodeWorkflow
          clear_declarations
          summary "Puts back the rows the newest migration of one store kept in legacy.db and removes its version, after a backup."

          sets :refusal, :version, :moved, :backup

          # How a down that fails after the check stops the call: a failed backup is exit 1, a refusal exit 3.
          STOPS = { Plastic::Graph::MigrationDown::BackupFailed => Failed, Plastic::Graph::MigrationDown::Refused => Refused,
                    Plastic::Graph::LegacyTable::Changed => Refused }.freeze

          def self.down(context) = Plastic::Graph::MigrationDown.new(context.scope.plastic_home, context.store, context.now)

          def self.run(context)
            undone = down(context).call
            context[:version] = undone.version
            context[:moved] = undone.moved
            context[:backup] = undone.backup
          rescue *STOPS.keys => error
            raise STOPS.fetch(error.class), error.message
          end

          # "1 row of document_revisions and 2 rows of sqlar".
          def self.counted(moved)
            parts = moved.map { |table, count| "#{count} #{(count == 1) ? "row" : "rows"} of #{table}" }
            [parts[0...-1].join(", "), parts.last].reject(&:empty?).join(" and ")
          end

          read "check the store can go down" do |context|
            context[:refusal] = down(context).refusal
          end

          gate "%{refusal}", stops: :refusal,
            words: "the store is not current, its newest migration kept nothing, or a row it kept changed since",
            pass: ->(context) { context.refusal.nil? }

          step "put the kept rows back", done: ->(context) { !context.version.nil? },
            changes: { databases: "The rows the newest migration kept in legacy.db go back into the store, and its version goes", backups: "A backup of the store is written first" } do |context|
            run(context)
          end

          read "say what was put back" do |context|
            context.print("down: put back #{counted(context.moved)} from legacy.db")
            context.print("down: #{context.store} no longer records migration #{context.version}")
          end

          outcome :done, offers: "plastic rollback",
            because: "%{store} has the layout of the release before migration %{version}, which plastic rollback switches back to"
        end
      end
    end
  end
end
