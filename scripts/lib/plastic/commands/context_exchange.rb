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
        row = graphs.databases.fetch(:knowledge).row("SELECT data FROM retrieval_contexts WHERE intent_id = :intent_id AND origin_id = :origin",
          intent_id:, origin: graphs.retrieval.origin_id)
        return JSON.parse(row.fetch("data")) if row

        JSON.parse(File.read(context_path))
      end

      def discovery
        row = graphs.databases.fetch(:knowledge).row("SELECT data FROM retrieval_discoveries WHERE intent_id = :intent_id AND origin_id = :origin",
          intent_id:, origin: graphs.retrieval.origin_id)
        return JSON.parse(row.fetch("data")) if row

        JSON.parse(File.read(discovery_path))
      end

      def context_path = File.join(scope.root, "context", "#{intent_id}.json")

      def discovery_path = File.join(scope.root, "discovery", "#{intent_id}.json")

      def source = (@source ||= ContextSource.new(scope))

      def submission = (@submission ||= ContextSubmission.new(intent_id:, discovery:, source:))

      def persistence = (@persistence ||= ContextPersistence.new(graphs:, scope:, intent_id:))

      def freshness = (@freshness ||= ContextFreshness.new(graphs:, scope:, source:))
    end
  end
end
