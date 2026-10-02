# frozen_string_literal: true

require_relative "../cli/command"
require "fileutils"
require "json"
require "tempfile"

module Plastic
  module Commands
    # Builds the retrieval handoff manifest; the harness chooses its evidence.
    class IntentDiscover < CLI::Command
      argument :intent_id, label: "ID", text: "the owning intent"
      argument :terms, label: "TERMS", text: "literal search terms", rest: true
      option :source_projects, switch: "--source-project SLUG", text: "a source store", repeatable: true
      reads :knowledge
      writes :knowledge

      def call
        validate_intent!
        output.row("discovery", persist(manifest))
        output.next_step("plastic intent context #{parsed.fetch(:intent_id)} --from FILE", because: "an agent selects evidence and provides architecture context")
      rescue Graph::RetrievalGraph::MaintenanceRequired => error
        raise CLI::Command::Failure, error.message
      end

      private

      def validate_intent!
        id = parsed.fetch(:intent_id)
        raise CLI::Command::Usage, "invalid intent id #{id.inspect}" unless /\A\d+[a-z0-9]*\z/.match?(id)
        raise CLI::Command::Failure, "no intent #{id} in owning store" unless Graph.open(home: scope.plastic_home, store: scope.slug).retrieval.intent(id)
      end

      def manifest
        source_scope = sources
        { intent_id: parsed.fetch(:intent_id), query: parsed.fetch(:terms), scope: source_scope, candidates: candidates,
          workflow: ExternalAgentWorkflow.retrieval_handoff(intent_id: parsed.fetch(:intent_id), terms: parsed.fetch(:terms), sources: source_scope) }
      end

      def sources
        configured_sources.tap { |list| validate_sources(list) }
      end

      def configured_sources
        values = parsed.fetch(:source_projects)
        values = environment.env.fetch("PLASTIC_SOURCE_PROJECTS", "").split(",") if values.empty?
        canonical_sources(values).then { |list| list.empty? ? [scope.slug] : list }
      end

      def canonical_sources(values) = values.map(&:strip).reject(&:empty?).uniq.sort

      def validate_sources(list)
        unknown = list - scope.known_slugs
        raise CLI::Command::Failure, "unknown source projects: #{unknown.join(", ")}" if unknown.any?
      end

      def candidates
        sources.flat_map { |slug| rows(slug) }.sort_by { |row| [-row.fetch("rrf_score"), row.fetch("uri")] }
      end

      def rows(slug)
        retrieval = maintained_retrieval(slug)
        retrieval.search(parsed.fetch(:terms), migrate: false).each_with_index.map do |row, index|
          reference = retrieval.search_reference(row)
          row.merge(reference.transform_keys(&:to_s)).merge("store" => slug, "local_rank" => index + 1,
            "rrf_score" => 1.0 / (61 + index), "archived" => retrieval.archived?(row.fetch("intent_id")))
        end
      end

      def maintained_retrieval(slug)
        missing = Graph::Schema::STORE.map { |key| Graph::Schema.file(key) }.reject do |file|
          File.file?(File.join(scope.plastic_home, "stores", slug, file))
        end
        raise Graph::RetrievalGraph::MaintenanceRequired, "retrieval maintenance is required before source #{slug} can be read" if missing.any?

        Graph.open(home: scope.plastic_home, store: slug).retrieval
      end

      def persist(document)
        FileUtils.mkdir_p(File.dirname(manifest_path))
        Tempfile.create(["discovery", ".json"], File.dirname(manifest_path)) do |file|
          file.write(JSON.pretty_generate(document))
          file.flush
          File.rename(file.path, manifest_path)
        end
        document
      end

      def manifest_path = File.join(scope.root, "discovery", "#{parsed.fetch(:intent_id)}.json")
    end
  end
end
