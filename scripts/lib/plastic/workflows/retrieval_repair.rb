# frozen_string_literal: true

require "shellwords"
require_relative "../cli/scope"
require_relative "../graph/retrieval_graph"
require_relative "../graph/retrieval/maintained_store"

module Plastic
  module Workflows
    # The problem a read prints for a store it refused: a store that needs
    # retrieval maintenance names the command that readies it, the installer
    # for the global store and project new for a project store.
    class RetrievalRepair
      # Nil when every store in `slugs` is maintained; otherwise the problem
      # of the first store that is not.
      def self.check(scope, slugs)
        slugs.each { |slug| Graph::Retrieval::MaintainedStore.new(scope.plastic_home, slug).verify }
        nil
      rescue Graph::RetrievalGraph::MaintenanceRequired => error
        new(scope, error).problem
      end

      def initialize(scope, error)
        @scope = scope
        @error = error
      end

      def problem = slug ? "#{message}; run #{command}, then try again" : message

      private

      attr_reader :scope, :error

      def message = error.message

      def slug = (error.slug if error.is_a?(Graph::RetrievalGraph::MaintenanceRequired))

      def command
        return "plastic install --reinstall" if slug == CLI::Scope::GLOBAL

        folder = scope.projects[slug]
        "plastic project new #{slug} #{folder ? Shellwords.escape(folder) : "PATH"}"
      end
    end
  end
end
