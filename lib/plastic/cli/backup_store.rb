# frozen_string_literal: true

require_relative "command"
require_relative "../graph/backup/databases"

module Plastic
  class CLI
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
        raise Usage, "name the store with --store; --project does not apply" if parsed[:project]
      end

      def refuse_unregistered
        slug = parsed[:store]
        projects = scope.projects
        return if slug == Scope::GLOBAL || projects.key?(slug)

        raise Usage, "no registered project named #{slug.inspect}; the projects are #{projects.keys.sort.join(", ")}"
      end

      def one_of(keys, give:, both:)
        given = keys.count { |key| parsed[key] }
        raise Usage, give if given.zero?
        raise Usage, both if given > 1
      end

      def as_usage(error_class)
        yield
      rescue error_class => error
        raise Usage, error.message
      end

      def database_list = as_usage(Plastic::Graph::Backup::Databases::Unknown) { Plastic::Graph::Backup::Databases.parse(parsed[:databases]) }

      def new_scope
        Scope.new(env: environment.env, home: environment.home, slug: parsed[:store], directory: environment.directory)
      end
    end
  end
end
