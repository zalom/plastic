# frozen_string_literal: true

module Plastic
  module Commands
    # Resolves the selected retrieval stores for a search request.
    class SearchScope
      def initialize(scope, parsed, environment)
        @scope = scope
        @parsed = parsed
        @environment = environment
      end

      def sources
        selected = SearchSourceList.new(configured_sources).canonical
        selected = [scope.slug] if selected.empty?
        validate_sources(selected)
        selected
      end

      private

      attr_reader :environment, :parsed, :scope

      def configured_sources
        values = parsed.fetch(:source_projects)
        values.empty? ? environment.env.fetch("PLASTIC_SOURCE_PROJECTS", "").split(",") : values
      end

      def validate_sources(sources)
        unknown = sources - scope.known_slugs
        return if unknown.empty?

        raise CLI::Command::Usage, "unknown source projects: #{unknown.join(", ")}"
      end
    end

    # Canonicalizes source names before the command resolves a store.
    class SearchSourceList
      def initialize(values)
        @values = values
      end

      def canonical = values.map(&:strip).reject(&:empty?).uniq.sort

      private

      attr_reader :values
    end
  end
end
