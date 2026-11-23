# frozen_string_literal: true

require "shellwords"
require_relative "../../../code_workflow"
require_relative "../../../graph"
require_relative "../../../graph/knowledge/store_folder"
require_relative "../../../graph/work/store_resume"
require_relative "../../worktree"

module Plastic
  module Workflows
    module Code
      module Graph
        # Says where each named store's work stopped and what runs next. It reads
        # the rows and writes nothing.
        class Resume < CodeWorkflow
          SEVERAL = "store %s is the first named with work; each then: line holds a store's own next command"

          clear_declarations

          sets :next_command, :why

          read "refuse --stores with --project" do |context|
            raise Usage, "--stores names the stores; --project does not apply" if context.stores && context.scope.requested?
          end

          read "print where each store's work stopped" do |context|
            reports = store_slugs(context).map { |slug| report(context, slug) }
            reports.each { |found| found.rows.each { |label, value| context.row(label, value) } }
            offer_next(context, reports)
          end

          outcome :done, offers: "%{next_command}", because: "%{why}",
            words: "every named store has reported where its work stopped, and the reason names the first store with work"

          def self.store_slugs(context)
            stores = context.stores
            stores ? named(context, stores) : [context.scope.slug]
          end

          def self.named(context, stores)
            names = stores.split(",").map(&:strip).uniq
            raise Usage, "name at least one store after --stores" if names.empty?

            names.each { |name| refuse_unregistered(context.scope, name) }
          end

          def self.refuse_unregistered(scope, name)
            projects = scope.projects
            return if name == Scope::GLOBAL || projects.key?(name)

            raise Usage, "no registered project named #{name.inspect}; the projects are #{projects.keys.sort.join(", ")}"
          end

          def self.report(context, slug)
            scope = context.scope
            home = scope.plastic_home
            session = context.session
            retrieval = Plastic::Graph.open(home:, store: slug, session:, clock: context.clock).retrieval
            Plastic::Graph::Work::StoreResume.new(retrieval, Plastic::Graph::Knowledge::StoreFolder.new(File.join(home, "stores", slug)), session, now: context.now, work: Plastic::Workflows::Worktree.work(scope, slug))
          end

          def self.offer_next(context, reports)
            found = reports.find(&:next_step)
            return say(context, "plastic status", "no store has open work") unless found

            command, why = found.next_step
            slug = found.slug
            say(context, in_store(context.scope, command, slug), reports.one? ? why : format(SEVERAL, slug))
          end

          def self.say(context, command, why)
            context[:next_command] = command
            context[:why] = why
          end

          def self.in_store(scope, command, slug)
            return command if slug == scope.slug || command.include?("--project")

            "#{command} --project #{Shellwords.escape(slug)}"
          end
        end
      end
    end
  end
end
