# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../cli/command/usage"
require_relative "../graph/knowledge/backup/databases"

module Plastic
  module Workflows
    # Replaces the databases of one store with those of a done backup, after
    # a safety backup of the current ones.
    class BackupRestore < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :folder, :refusal, :safety, :restored

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
        names = Graph::Knowledge::Backup::Databases.parse(context.databases)
        context.work.backups.restorer.held_in(folder, names:)
      rescue Graph::Knowledge::Backup::Restorer::Missing => error
        raise CLI::Command::Usage, error.message
      end

      read "choose the backup" do |context|
        context[:folder] = choose(context)
        held(context, context.folder)
        context[:refusal] = context.work.backups.restorer.refusal(context.folder)
      end

      gate "%{refusal}", stops: :refusal, pass: ->(context) { context.refusal.nil? }

      step "replace the databases", done: ->(context) { !context.safety.nil? } do |context|
        names = Graph::Knowledge::Backup::Databases.parse(context.databases)
        context[:safety] = context.work.backups.restore(context.folder, databases: names)
        context[:restored] = held(context, context.folder)
      end

      read "say what was replaced" do |context|
        context.print("restore: backed up the current databases as #{context.safety}")
        context.restored.each { |name| context.print("restore: #{name} from #{context.folder}") }
      end

      outcome :done, offers: "plastic sync down --project %{store}",
        because: "the rows are restored and the files are not; sync down writes the files from the rows"
    end
  end
end
