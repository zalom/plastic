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
      reads :work, :knowledge
      option :stores, switch: "--stores LIST", text: "the stores to read, comma separated: registered projects or global; the call's own store when left out"

      def call
        refuse_project
        reports = store_slugs.map { |slug| report(slug) }
        reports.each { |found| found.rows.each { |label, value| output.row(label, value) } }
        offer_next(reports)
      end

      private

      def refuse_project
        raise CLI::Command::Usage, "--stores names the stores; --project does not apply" if parsed[:stores] && parsed[:project]
      end

      def store_slugs
        names = parsed[:stores]&.split(",")&.map(&:strip)&.uniq
        return [scope.slug] if names.nil?

        raise CLI::Command::Usage, "name at least one store after --stores" if names.empty?

        names.each { |name| refuse_unregistered(name) }
      end

      def refuse_unregistered(name)
        projects = scope.projects
        return if name == CLI::Scope::GLOBAL || projects.key?(name)

        raise CLI::Command::Usage, "no registered project named #{name.inspect}; the projects are #{projects.keys.sort.join(", ")}"
      end

      def report(slug)
        retrieval = Graph.open(home: scope.plastic_home, store: slug, session: environment.session).retrieval
        folder = Graph::Knowledge::StoreFolder.new(File.join(scope.plastic_home, "stores", slug))
        Graph::Work::StoreResume.new(retrieval, folder, environment.session)
      end

      def offer_next(reports)
        found = reports.find(&:next_step)
        return output.next_step("plastic status", because: "no store has open work") unless found

        command, why = found.next_step
        output.next_step(in_store(command, found.slug), because: reports.size > 1 ? several(found.slug) : why)
      end

      def several(slug) = "store #{slug} is the first named with work; each then: line holds a store's own next command"

      def in_store(command, slug)
        return command if slug == scope.slug || command.include?("--project")

        "#{command} --project #{Shellwords.escape(slug)}"
      end
    end
  end
end
