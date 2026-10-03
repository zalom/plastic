# frozen_string_literal: true

require_relative "../graph/context_freshness"
require_relative "../graph/context_source"
require_relative "context_documents"

module Plastic
  module Workflows
    # Reads the saved context and reports whether its evidence is still current.
    class ContextReadback
      def initialize(context)
        @context = context
      end

      def call
        document = ContextDocuments.new(context).read(:context)
        document.merge("freshness" => Graph::ContextFreshness.new(source: Graph::ContextSource.new(context.scope.plastic_home)).call(document))
      end

      private

      attr_reader :context
    end
  end
end
