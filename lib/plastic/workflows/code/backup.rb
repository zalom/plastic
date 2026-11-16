# frozen_string_literal: true

require_relative "../../code_workflow"
require_relative "../../graph/backup/databases"

module Plastic
  module Workflows
    module Code
      # Copies the databases of one store into a new backup folder, and writes
      # the row that names it.
      class Backup < CodeWorkflow
        clear_declarations
        summary "Copies the databases of one store into a new backup folder and writes the row that names it."

        sets :name, :files, :bytes

        step "write the backup folder", done: ->(context) { !context.name.nil? },
          changes: { backups: "A backup folder with a copy of each chosen database is written" } do |context|
          row = context.work.backups.write(databases: Plastic::Graph::Backup::Databases.parse(context.databases), live: context.scope.live)
          context[:name] = row.fetch(:name)
          context[:files] = row.fetch(:files)
          context[:bytes] = row.fetch(:bytes)
        end

        read "say what was copied" do |context|
          files = context.files
          context.print("backup: #{context.name}, #{files} #{(files == 1) ? "database" : "databases"}, #{context.bytes} bytes")
        end

        outcome :done, offers: "plastic backup list --store %{store}", because: "backup %{name} is on disk"
      end
    end
  end
end
