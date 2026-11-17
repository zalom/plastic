# frozen_string_literal: true

require_relative "../backup"
require_relative "../../../code_workflow"
require_relative "../../../cli/command/usage"
require_relative "../../../graph/backup/databases"
require_relative "../../schema_migration"

module Plastic
  module Workflows
    module Code
      class Backup
        # Replaces the databases of one store with those of a done backup, after
        # a safety backup of the current ones.
        class Restore < CodeWorkflow
          clear_declarations
          summary "Replaces the databases of one store with those of a done backup, after a safety backup."

          sets :folder, :refusal, :safety, :restored, :migrated

          # The backup folder the call names, or a usage error that names what is missing.
          def self.choose(context)
            folder = context.latest ? context.work.backups.latest_done : context.timestamp
            raise CLI::Command::Usage, "no done backup of #{context.store} to restore" unless folder

            present(context, folder)
          end

          def self.present(context, folder)
            return folder if context.work.backups.folders.exist?(folder)

            raise CLI::Command::Usage, "no backup #{folder.inspect} of #{context.store}"
          end

          # The database names the restore replaces; a name the backup lacks is a usage error.
          def self.held(context, folder)
            names = Plastic::Graph::Backup::Databases.parse(context.databases)
            context.work.backups.restorer.held_in(folder, names:)
          rescue Plastic::Graph::Backup::Restorer::Missing => error
            raise CLI::Command::Usage, error.message
          end

          read "choose the backup" do |context|
            context[:folder] = choose(context)
            held(context, context.folder)
            context[:refusal] = context.work.backups.restorer.refusal(context.folder, databases: Plastic::Graph::Backup::Databases.parse(context.databases))
          end

          gate "%{refusal}", stops: :refusal,
            words: "an intent of the store holds a fresh delivery lock, or the backup is not done",
            pass: ->(context) { context.refusal.nil? }

          step "replace the databases", done: ->(context) { !context.safety.nil? },
            changes: { databases: "The chosen databases of the store are replaced by the copies of the backup folder", backups: "A safety backup of the replaced databases is written" } do |context|
            names = Plastic::Graph::Backup::Databases.parse(context.databases)
            context[:safety] = context.work.backups.restore(context.folder, databases: names)
            context[:restored] = held(context, context.folder)
          end

          step "bring the restored store to the newest layout", done: ->(context) { !context.migrated.nil? },
            changes: { databases: "The restored databases are migrated to the newest layout" } do |context|
            context[:migrated] = SchemaMigration.bring_current(context, slug: context.store).migrated
          end

          read "say what was replaced" do |context|
            context.print("restore: backed up the current databases as #{context.safety}")
            context.restored.each { |name| context.print("restore: #{name} from #{context.folder}") }
          end

          outcome :done, offers: nil,
            because: "the rows are restored and the files are not; ask the person whether to run plastic sync down, which writes the files from the rows, or plastic sync up, which reads the files into the rows"
        end
      end
    end
  end
end
