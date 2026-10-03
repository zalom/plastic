# frozen_string_literal: true

module Plastic
  module Workflows
    # Resolves the selected stores for a retrieval discovery request.
    class DiscoveryScope
      def self.resolve(context)
        new(context).resolve
      end

      def initialize(context)
        @context = context
      end

      def resolve
        selected = source_values
        selected = [@context.scope_slug] if selected.empty?
        validate(selected)
        selected
      end

      private

      def source_values
        values = @context.source_projects
        (values.empty? ? ENV.fetch("PLASTIC_SOURCE_PROJECTS", "").split(",") : values).map(&:strip).reject(&:empty?).uniq.sort
      end

      def validate(selected)
        unknown = selected - (known_stores | ["global"])
        raise CLI::Command::Failure, "unknown source projects: #{unknown.join(", ")}" if unknown.any?
      end

      def known_stores
        Dir.glob(File.join(@context.plastic_home, "stores", "*")).filter_map do |path|
          File.basename(path) if File.directory?(path)
        end
      end
    end
  end
end
