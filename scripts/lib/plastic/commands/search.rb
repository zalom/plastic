# frozen_string_literal: true

require_relative "../cli/command"
require_relative "../graph/retrieval_source"

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
      rescue Graph::RetrievalGraph::InvalidSearch => error
        raise CLI::Command::Usage, error.message
      rescue Graph::RetrievalGraph::MaintenanceRequired => error
        raise CLI::Command::Failure, error.message
      end

      private

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
        raise CLI::Command::Usage, "unknown source projects: #{unknown.join(", ")}" if unknown.any?
      end

      def rows(slug)
        retrieval = maintained_retrieval(slug)
        retrieval.search(parsed.fetch(:terms), limit: search_limit, migrate: false).each_with_index.map do |row, index|
          result_row(retrieval, slug, row, index + 1)
        end
      end

      def maintained_retrieval(slug)
        missing = Graph::Schema::STORE.map { |key| Graph::Schema.file(key) }.reject do |file|
          File.file?(File.join(scope.plastic_home, "stores", slug, file))
        end
        raise Graph::RetrievalGraph::MaintenanceRequired, "retrieval maintenance is required before source #{slug} can be read" if missing.any?

        Graph.open_retrieval(home: scope.plastic_home, store: slug)
      end

      def result_row(retrieval, slug, row, rank)
        reference = retrieval.search_reference(row)
        details = { "store" => slug, "local_rank" => rank, "rrf_score" => rrf(rank), "archived" => retrieval.archived?(row.fetch("intent_id")) }
        row.merge(reference.transform_keys(&:to_s)).merge(details).merge("body" => excerpt(row.fetch("body")))
      end

      def excerpt(body)
        normalized, positions = normalized_positions(body)
        index = search_terms.filter_map { |term| normalized.index(normalize(term)) }.min || 0
        index = positions.fetch(index, 0)
        first = [index - 160, 0].max
        body[first, 320]
      end

      def search_terms = parsed.fetch(:terms).scan(/[\p{Alnum}_]+/)

      def normalize(text) = text.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase

      def normalized_positions(text)
        positions = []
        normalized = text.each_char.with_index.map do |character, index|
          fragment = normalize(character)
          positions.concat([index] * fragment.length)
          fragment
        end.join
        [normalized, positions]
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
