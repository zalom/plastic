# frozen_string_literal: true

require "shellwords"
require_relative "../cli/command"
require_relative "../graph"
require_relative "../graph/knowledge/store_folder"
require_relative "../graph/work/store_resume"

module Plastic
  module Commands
    # Says where each named store's work stopped and what runs next. It reads
    # the rows and writes nothing.
    class GraphResume < CLI::Command
      SEVERAL = "store %s is the first named with work; each then: line holds a store's own next command"

      reads :work, :knowledge
      option :stores, switch: "--stores LIST", text: "the stores to read, comma separated: registered projects or global; the call's own store when left out"

      def call
        refuse_project
        offer_next(store_slugs.map { |slug| report(slug) }.each { |found| print_rows(found) })
      end

      private

      def print_rows(found)
        found.rows.each { |label, value| output.row(label, value) }
      end

      def refuse_project
        raise CLI::Command::Usage, "--stores names the stores; --project does not apply" if parsed[:stores] && parsed[:project]
      end

      def store_slugs
        stores = parsed[:stores]
        stores ? named(stores) : [scope.slug]
      end

      def named(stores)
        names = stores.split(",").map(&:strip).uniq
        raise CLI::Command::Usage, "name at least one store after --stores" if names.empty?

        names.each { |name| refuse_unregistered(name) }
      end

      def refuse_unregistered(name)
        projects = scope.projects
        return if name == CLI::Scope::GLOBAL || projects.key?(name)

        raise CLI::Command::Usage, "no registered project named #{name.inspect}; the projects are #{projects.keys.sort.join(", ")}"
      end

      def report(slug)
        home = scope.plastic_home
        session = environment.session
        retrieval = Graph.open(home:, store: slug, session:).retrieval
        Graph::Work::StoreResume.new(retrieval, Graph::Knowledge::StoreFolder.new(File.join(home, "stores", slug)), session)
      end

      def offer_next(reports)
        found = reports.find(&:next_step)
        return output.next_step("plastic status", because: "no store has open work") unless found

        offer(found, reports)
      end

      def offer(found, reports)
        command, why = found.next_step
        slug = found.slug
        output.next_step(in_store(command, slug), because: reports.one? ? why : format(SEVERAL, slug))
      end

      def in_store(command, slug)
        return command if slug == scope.slug || command.include?("--project")

        "#{command} --project #{Shellwords.escape(slug)}"
      end
    end
  end
end
