# frozen_string_literal: true

require_relative "../cli/command"
require_relative "../graph"

module Plastic
  module Commands
    # Searches literal indexed passages in the selected local stores.
    class Search < CLI::Command
      argument :terms, label: "TERMS", text: "literal search terms", rest: true
      option :source_projects, switch: "--source-project SLUG", text: "a source store", repeatable: true
      option :limit, switch: "--limit N", text: "maximum passages", default: 20
      reads :knowledge

      def call
        output.row("results", ranked_rows)
        output.next_step("none", because: "the indexed passages were read")
      rescue Graph::RetrievalGraph::InvalidSearch, Graph::RetrievalGraph::MaintenanceRequired => error
        raise CLI::Command::Failure, error.message
      end

      private

      def sources
        values = parsed.fetch(:source_projects)
        values = environment.env.fetch("PLASTIC_SOURCE_PROJECTS", "").split(",") if values.empty?
        values = [scope.slug] if values.empty?
        values.map(&:strip).reject(&:empty?).uniq.sort.tap { |list| validate_sources(list) }
      end

      def validate_sources(list)
        unknown = list - scope.known_slugs
        raise CLI::Command::Failure, "unknown source projects: #{unknown.join(", ")}" if unknown.any?
      end

      def rows(slug)
        retrieval = Graph.open(home: scope.plastic_home, store: slug).retrieval
        retrieval.search(parsed.fetch(:terms), limit: search_limit, migrate: false).each_with_index.map do |row, index|
          result_row(retrieval, slug, row, index + 1)
        end
      end

      def result_row(retrieval, slug, row, rank)
        reference = retrieval.reference(row.fetch("intent_id"), row.fetch("path"))
        details = { "store" => slug, "local_rank" => rank, "rrf_score" => rrf(rank) }
        row.merge(reference.transform_keys(&:to_s)).merge(details)
      end

      def ranked_rows = sources.flat_map { |slug| rows(slug) }.sort_by { |row| [-row.fetch("rrf_score"), row.fetch("uri")] }.take(search_limit)

      def rrf(rank) = 1.0 / (60 + rank)

      def search_limit
        Integer(parsed.fetch(:limit))
      rescue ArgumentError, TypeError
        raise Graph::RetrievalGraph::InvalidSearch, "search limit must be an integer"
      end
    end
  end
end
