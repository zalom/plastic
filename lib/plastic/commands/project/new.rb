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
          target = Target.new(slug: checked_slug, path: checked_path)
          register(target)
          make_ready(target.slug)
          name_written(target)
          announce(target)
        end

        private

        def checked_slug = CLI::ProjectName.new(parsed[:slug]).checked

        def checked_path
          path = File.expand_path(parsed[:path], environment.directory)
          raise Failed, "#{path} is not a directory" unless File.directory?(path)

          path
        end

        def register(target)
          target.register_in(CLI::ProjectsFile.new(File.join(scope.plastic_home, "projects.yml")), scope.projects)
        end

        def make_ready(slug)
          Plastic::Graph.create(home: scope.plastic_home, store: slug, session: environment.session)
        end

        def name_written(target)
          target.created_line&.then { |line| output.row("created", line) }
        end

        def announce(target)
          slug = target.slug
          output.row("project", target.summary)
          output.next_step("plastic intent new TITLE --project #{slug}", because: "the project is registered and its store is ready")
        end

        Target = Data.define(:slug, :path) do
          def register_in(file, projects)
            known = projects[slug]
            return if known && CLI::ProjectsFile.same_folder?(known, path)
            raise Refused, "#{slug} is registered at #{known}, not at #{path}; edit projects.yml to move it" if known

            file.add(slug, path)
          end

          def created_line
            files = CLI::RuleFiles.new(path, slug).write_absent
            "#{files.join(" and ")} in #{path}" unless files.empty?
          end

          def summary = "#{slug}: #{path}"
        end
      end
    end
  end
end
