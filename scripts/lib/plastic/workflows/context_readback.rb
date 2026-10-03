# frozen_string_literal: true

require_relative "../graph/retrieval/context/freshness"
require_relative "../graph/retrieval/context/source"
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
        document.merge("freshness" => Graph::Retrieval::Context::Freshness.new(source: Graph::Retrieval::Context::Source.new(context.scope.plastic_home)).call(document))
      end

      private

      attr_reader :context
    end
  end
end
