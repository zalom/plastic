# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph"
require_relative "../../../graph/work/project_digest"

module Plastic
  module Workflows
    module Code
      module Project
        # Prints a short digest of each named project, then what the agent
        # checks, starts and keeps before the owner's next ask. It reads the rows
        # and the repository's files and writes nothing.
        class Load < CodeWorkflow
          THEN = "Check the architecture map of each coding project with a tool such as Enola, and start the MCP servers " \
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

            words.split(/[\s,]+/).reject(&:empty?).uniq.each { |name| refuse_unregistered(scope, name) }
          end

          def self.refuse_unregistered(scope, name)
            projects = scope.projects
            return if name == Scope::GLOBAL || projects.key?(name)

            raise Usage, "no registered project named #{name.inspect}; the projects are #{projects.keys.sort.join(", ")}"
          end

          def self.digest(context, slug)
            scope = context.scope
            home = scope.plastic_home
            store = File.join(home, "stores", slug)
            retrieval = (Plastic::Graph.open(home:, store: slug, session: context.session, clock: context.clock).retrieval if File.directory?(store))
            Plastic::Graph::Work::ProjectDigest.new(slug:, store:, repo: scope.projects[slug], retrieval:)
          end
        end
      end
    end
  end
end
