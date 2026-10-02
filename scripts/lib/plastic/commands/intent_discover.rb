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
        output.row("discovery", persist(manifest))
        output.next_step("none", because: "the retrieval candidates were recorded")
      end

      private

      def manifest
        { intent_id: parsed.fetch(:intent_id), query: parsed.fetch(:terms), scope: sources, candidates: candidates }
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
        retrieval = Graph.open(home: scope.plastic_home, store: slug).retrieval
        retrieval.search(parsed.fetch(:terms), migrate: false).each_with_index.map do |row, index|
          reference = retrieval.search_reference(row)
          row.merge(reference.transform_keys(&:to_s)).merge("store" => slug, "local_rank" => index + 1,
            "rrf_score" => 1.0 / (61 + index), "archived" => retrieval.archived?(row.fetch("intent_id")))
        end
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
