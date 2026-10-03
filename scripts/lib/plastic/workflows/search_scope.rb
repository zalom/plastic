# frozen_string_literal: true

require_relative "../cli/command/usage"

module Plastic
  module Workflows
    # Resolves the selected retrieval stores for a search request.
    class SearchScope
      def initialize(context)
        @context = context
      end

      def sources
        selected = configured.map(&:strip).reject(&:empty?).uniq.sort
        selected = [context.scope.slug] if selected.empty?
        validate(selected)
        selected
      end

      private

      attr_reader :context

      def configured
        values = context.source_projects
        values.empty? ? context.scope.setting("PLASTIC_SOURCE_PROJECTS", "").split(",") : values
      end

      def validate(selected)
        unknown = selected - context.scope.known_slugs
        return if unknown.empty?

        raise CLI::Command::Usage, "unknown source projects: #{unknown.join(", ")}"
      end
    end
  end
end
