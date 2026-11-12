# frozen_string_literal: true

require_relative "external_agent_workflow"
require_relative "../graph/retrieval/maintained_store"
require_relative "../graph/retrieval/source"
require_relative "discovery_candidates"

module Plastic
  module Workflows
    # Builds the deterministic candidate manifest handed to an external agent.
    class DiscoveryManifest
      def self.build(context, source_scope)
        new(context, source_scope).build
      end

      def initialize(context, source_scope)
        @context = context
        @source_scope = source_scope
      end

      def build
        { intent_id: @context.intent_id, query: @context.terms, scope: @source_scope,
          candidates: candidates, workflow: handoff }
      end

      private

      def candidates
        @source_scope.flat_map { |slug| rows(slug) }.sort_by { |row| [-row.fetch("rrf_score"), row.fetch("uri")] }
      end

      def rows(slug) = DiscoveryCandidates.new(slug, retrieval_for(slug)).rows(@context.terms)

      def retrieval_for(slug)
        home = @context.scope.plastic_home
        Graph::Retrieval::MaintainedStore.new(home, slug).verify
        Graph.open_retrieval(home:, store: slug)
      end

      def handoff
        search = ExternalAgentWorkflow.search_command(@context.terms, @source_scope)
        ExternalAgentWorkflow.retrieval_handoff(intent_id: @context.intent_id, project: @context.scope.slug, search:)
      end
    end
  end
end
