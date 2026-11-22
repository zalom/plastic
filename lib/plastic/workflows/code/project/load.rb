# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph"
require_relative "../../../graph/work/project_digest"
require_relative "../../../graph/work/play_rows"

module Plastic
  module Workflows
    module Code
      module Project
        # Prints a short digest of each named project, then what the agent
        # checks, starts and keeps before the owner's next ask. It reads the rows, the retrieval graph
        # and the repository's files and writes nothing.
        class Load < CodeWorkflow
          THEN = "Check the architecture map of each coding project with an architecture mapping tool such as Enola, and " \
            "start the MCP servers " \
            "and apps that each project's AGENTS.md names for its work; Plastic starts nothing. Keep these digests as the " \
            "projects' context, look up the rest with plastic search, and run plastic project load again to refresh them. " \
            "Wait for the owner's next prompt before picking any work."

          clear_declarations

          read "refuse project names with --project" do |context|
            raise Usage, "the words name the projects; --project does not apply" if context.slugs && context.scope.requested?
          end

          read "print a digest of each project" do |context|
            slugs(context).each { |slug| digest(context, slug).rows.each { |label, value| context.row(label, value) } }
            context.row("then:", THEN)
          end

          outcome :done, offers: nil, because: "the projects are loaded; the next work waits for the owner's ask"

          def self.slugs(context)
            words = context.slugs
            scope = context.scope
            return [scope.slug] unless words

            names = words.split(/[\s,]+/).reject(&:empty?).uniq
            raise Usage, "name at least one project" if names.empty?

            names.each { |name| refuse_unregistered(scope, name) }
          end

          def self.refuse_unregistered(scope, name)
            projects = scope.projects
            return if name == Scope::GLOBAL || projects.key?(name)

            raise Usage, "no registered project named #{name.inspect}; the projects are #{projects.keys.sort.join(", ")}"
          end

          def self.digest(context, slug)
            scope = context.scope
            store = File.join(scope.plastic_home, "stores", slug)
            work, note = read_store(context, slug, store)
            Plastic::Graph::Work::ProjectDigest.new(slug:, store:, repo: repo_path(scope, slug), work:, note:)
          end

          # The registered path as the project lookup reads it: an empty one is no path, and the rest is expanded.
          def self.repo_path(scope, slug)
            path = scope.projects[slug].to_s
            File.expand_path(path) unless path.empty?
          end

          # The rows of the work in play, with the passages the retrieval graph gives for it, or nil and a note that says
          # why the store cannot be read. A store opens only when every database file is there, since opening builds a
          # missing one, and a store out of step stops only its own digest.
          def self.read_store(context, slug, store)
            return [nil, "missing"] unless File.directory?(store)
            lacking = missing_files(store)
            return [nil, lost(lacking)] if lacking.any?

            retrieval = Plastic::Graph.open(home: context.scope.plastic_home, store: slug, session: context.session, clock: context.clock).retrieval
            [Plastic::Graph::Work::PlayRows.new(retrieval, slug).rows, nil]
          rescue Plastic::Graph::OutOfStep => error
            [nil, "out of step with this code; run #{error.next_command}"]
          end

          def self.missing_files(store) = Plastic::Graph::Database::Store::FILES.reject { |name| File.file?(File.join(store, name)) }

          def self.lost(lacking) = (lacking.size == Plastic::Graph::Database::Store::FILES.size) ? "holds no database files" : "missing #{lacking.join(", ")}"
        end
      end
    end
  end
end
