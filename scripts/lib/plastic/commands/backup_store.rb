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
        return if scope.projects.key?(parsed[:store])

        raise CLI::Command::Usage, "no registered project named #{parsed[:store].inspect}; the projects are #{scope.projects.keys.sort.join(", ")}"
      end

      def database_list
        Graph::Knowledge::Backup::Databases.parse(parsed[:databases])
      rescue Graph::Knowledge::Backup::Databases::Unknown => error
        raise CLI::Command::Usage, error.message
      end

      def scope
        @scope ||= CLI::Scope.new(env: environment.env, home: environment.home, slug: parsed[:store], directory: environment.directory)
      end
    end
  end
end
