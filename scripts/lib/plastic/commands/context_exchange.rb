# frozen_string_literal: true

module Plastic
  module Commands
    # Reads a saved context or validates and persists a submitted replacement.
    class ContextExchange
      def initialize(graphs:, scope:, intent_id:, submission_path:)
        @graphs = graphs
        @scope = scope
        @intent_id = intent_id
        @submission_path = submission_path
      end

      def call
        return readback unless submission_path

        persistence.persist(submission.validate(submission_path))
      end

      private

      attr_reader :graphs, :scope, :intent_id, :submission_path

      def readback
        document = stored_context
        document.merge("freshness" => freshness.call(document))
      rescue Errno::ENOENT
        raise CLI::Command::Failure, "no retrieval context for intent #{intent_id}"
      end

      def stored_context
        documents.read(:context)
      end

      def discovery = documents.read(:discovery)

      def source = (@source ||= ContextSource.new(scope))

      def documents = (@documents ||= ContextDocuments.new(graphs:, scope:, intent_id:))

      def submission = (@submission ||= ContextSubmission.new(intent_id:, discovery:, source:))

      def persistence = (@persistence ||= ContextPersistence.new(graphs:, scope:, intent_id:))

      def freshness = (@freshness ||= ContextFreshness.new(graphs:, scope:, source:))
    end
  end
end
