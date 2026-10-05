# frozen_string_literal: true

require_relative "../cli/command"
require_relative "../graph/knowledge/backup/databases"

module Plastic
  module Commands
    # What every backup command shares: it works on one registered store,
    # named by --store and never found from the working directory.
    module BackupStore
      def self.included(command)
        command.option :store, switch: "--store SLUG", required: true, text: "the registered project whose backups the call works on"
      end

      def call
        refuse_project
        refuse_unregistered
        check_call
        super
      end

      private

      def check_call = nil

      def refuse_project
        raise CLI::Command::Usage, "name the store with --store; --project does not apply" if parsed[:project]
      end

      def refuse_unregistered
        slug = parsed[:store]
        projects = scope.projects
        return if projects.key?(slug)

        raise CLI::Command::Usage, "no registered project named #{slug.inspect}; the projects are #{projects.keys.sort.join(", ")}"
      end

      def one_of(first, second, give:, both:)
        given = [first, second].count { |key| parsed[key] }
        raise CLI::Command::Usage, give if given.zero?
        raise CLI::Command::Usage, both if given > 1
      end

      def as_usage(error_class)
        yield
      rescue error_class => error
        raise CLI::Command::Usage, error.message
      end

      def database_list = as_usage(Graph::Knowledge::Backup::Databases::Unknown) { Graph::Knowledge::Backup::Databases.parse(parsed[:databases]) }

      def scope
        @scope ||= CLI::Scope.new(env: environment.env, home: environment.home, slug: parsed[:store], directory: environment.directory)
      end
    end
  end
end
