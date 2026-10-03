# frozen_string_literal: true

require_relative "../external_agent_workflow"
require_relative "../graph/retrieval_source"

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

      def rows(slug)
        retrieval = retrieval_for(slug)
        retrieval.search(@context.terms, migrate: false).each_with_index.map do |row, index|
          candidate(row, index, slug, retrieval)
        end
      end

      def candidate(row, index, slug, retrieval)
        reference = retrieval.search_reference(row).transform_keys(&:to_s)
        row.merge(reference).merge("store" => slug, "local_rank" => index + 1,
          "rrf_score" => 1.0 / (61 + index), "archived" => retrieval.archived?(row.fetch("intent_id")))
      end

      def retrieval_for(slug)
        ensure_store_files!(slug)
        Graph.open_retrieval(home: @context.plastic_home, store: slug)
      end

      def ensure_store_files!(slug)
        root = File.join(@context.plastic_home, "stores", slug)
        missing = Graph::Schema::STORE.map { |key| Graph::Schema.file(key) }.reject { |file| File.file?(File.join(root, file)) }
        return if missing.empty?

        raise Graph::RetrievalGraph::MaintenanceRequired, "retrieval maintenance is required before source #{slug} can be read"
      end

      def handoff
        ExternalAgentWorkflow.retrieval_handoff(intent_id: @context.intent_id, terms: @context.terms,
          sources: @source_scope, project: @context.scope_slug)
      end
    end
  end
end
