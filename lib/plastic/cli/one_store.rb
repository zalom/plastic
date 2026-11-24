# frozen_string_literal: true

require_relative "command"
require_relative "../graph/backup/databases"

module Plastic
  class CLI
    # What every command on one registered store shares: --project names the store, and the working directory never
    # finds it. A project the machine does not know stops the call before it runs.
    module OneStore
      # The one fact the workflows of these commands read: the project the call names.
      module Facts
        def given_facts = super.merge(project: nil)
      end

      def self.included(command) = command.extend(Facts)

      def call
        refuse_missing_project
        check_call
        super
      end

      private

      def check_call = nil

      def refuse_missing_project
        raise Usage, "name the store with --project" unless parsed[:project]
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
    end
  end
end
