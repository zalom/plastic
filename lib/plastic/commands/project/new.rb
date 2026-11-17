# frozen_string_literal: true

require_relative "../../cli/command"
require_relative "../../cli/project_name"
require_relative "../../cli/projects_file"
require_relative "../../cli/rule_files"
require_relative "../../graph"

module Plastic
  module Commands
    module Project
      # Registers a project in projects.yml and leaves its store ready, so an
      # intent can be opened at once. The other lines of the file stay as they
      # are. The same name at the same path again changes nothing.
      class New < CLI::Command
        argument :slug, label: "SLUG", text: "the project's name: lowercase letters, digits and dashes"
        argument :path, label: "PATH", text: "the project's repository folder"
        writes :work, :knowledge
        changes(work: "The work database of the store is created if it is missing", knowledge: "The knowledge database of the store is created if it is missing", home: "The project is registered in projects.yml in the Plastic home")

        def call
          slug = checked_slug
          path = checked_path
          register(slug, path)
          make_ready(slug)
          name_written(CLI::RuleFiles.new(path, slug).write_absent, path)
          announce(slug, path)
        end

        private

        def checked_slug = CLI::ProjectName.new(parsed[:slug]).checked

        def checked_path
          path = File.expand_path(parsed[:path], environment.directory)
          raise CLI::Command::Failure, "#{path} is not a directory" unless File.directory?(path)

          path
        end

        def register(slug, path)
          known = scope.projects[slug]
          return if known && CLI::ProjectsFile.same_folder?(known, path)
          raise CLI::Command::Refusal, "#{slug} is registered at #{known}, not at #{path}; edit projects.yml to move it" if known

          CLI::ProjectsFile.new(File.join(scope.plastic_home, "projects.yml")).add(slug, path)
        end

        def make_ready(slug)
          Plastic::Graph.create(home: scope.plastic_home, store: slug, session: environment.session)
        end

        def name_written(files, path)
          output.row("created", "#{files.join(" and ")} in #{path}") unless files.empty?
        end

        def announce(slug, path)
          output.row("project", "#{slug}: #{path}")
          output.next_step("plastic intent new TITLE --project #{slug}", because: "the project is registered and its store is ready")
        end
      end
    end
  end
end
