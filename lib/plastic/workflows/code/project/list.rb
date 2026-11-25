# frozen_string_literal: true

require_relative "../../../code_workflow"

module Plastic
  module Workflows
    module Code
      module Project
        # Lists the projects of projects.yml, each with its path, and marks the
        # ones whose store folder is missing. It writes nothing.
        class List < CodeWorkflow
          NO_STORE = " (no store)"

          clear_declarations

          read "print each project with its path" do |context|
            context.scope.projects.sort.each do |slug, path|
              missing = File.directory?(File.join(context.scope.plastic_home, "stores", slug)) ? "" : NO_STORE
              context.row("project", "#{slug}: #{path}#{missing}")
            end
          end

          outcome :none, if: ->(context) { context.scope.projects.empty? }, offers: "plastic project new SLUG PATH",
            because: "no project is registered yet"
          outcome :done, offers: "plastic status", because: "the projects are listed"
        end
      end
    end
  end
end
