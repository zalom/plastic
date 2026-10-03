# frozen_string_literal: true

require_relative "../cli/command"
require_relative "../graph"
require_relative "context_persistence"
require_relative "context_freshness"
require_relative "context_source"
require_relative "context_submission"
require "fileutils"
require "json"
require "tempfile"

module Plastic
  module Commands
    # Persists the agent's selected evidence without judging its relevance.
    class IntentContext < CLI::Command
      argument :intent_id, label: "ID", text: "the owning intent"
      option :from, switch: "--from FILE", text: "JSON evidence selection and architecture context"
      reads :knowledge
      writes :knowledge

      def call
        validate_intent!
        output.row("context", context)
        output.next_step("none", because: "the retrieval context was read")
      rescue Errno::ENOENT, JSON::ParserError => error
        raise CLI::Command::Usage, error.message
      rescue Graph::RetrievalGraph::MaintenanceRequired, Graph::RetrievalGraph::MissingReference, KeyError => error
        raise CLI::Command::Failure, error.message
      end

      private

      def validate_intent!
        id = parsed.fetch(:intent_id)
        raise CLI::Command::Usage, "invalid intent id #{id.inspect}" unless /\A\d+[a-z0-9]*\z/.match?(id)
        raise CLI::Command::Failure, "no intent #{id} in owning store" unless Graph.open(home: scope.plastic_home, store: scope.slug).retrieval.intent(id)
      end

      def readback
        document = stored_context
        document.merge("freshness" => freshness.call(document))
      rescue Errno::ENOENT
        raise CLI::Command::Failure, "no retrieval context for intent #{parsed.fetch(:intent_id)}"
      end

      def discovery
        row = graphs.databases.fetch(:knowledge).row("SELECT data FROM retrieval_discoveries WHERE intent_id = :intent_id AND origin_id = :origin",
          intent_id: parsed.fetch(:intent_id), origin: graphs.retrieval.origin_id)
        return JSON.parse(row.fetch("data")) if row

        JSON.parse(File.read(discovery_path))
      end

      def context = parsed[:from] ? persistence.persist(submission.validate(parsed.fetch(:from))) : readback

      def context_path = File.join(scope.root, "context", "#{parsed.fetch(:intent_id)}.json")

      def stored_context
        row = graphs.databases.fetch(:knowledge).row("SELECT data FROM retrieval_contexts WHERE intent_id = :intent_id AND origin_id = :origin",
          intent_id: parsed.fetch(:intent_id), origin: graphs.retrieval.origin_id)
        return JSON.parse(row.fetch("data")) if row

        JSON.parse(File.read(context_path))
      end

      def discovery_path = File.join(scope.root, "discovery", "#{parsed.fetch(:intent_id)}.json")

      def source = (@source ||= ContextSource.new(scope))

      def submission = (@submission ||= ContextSubmission.new(intent_id: parsed.fetch(:intent_id), discovery:, source:))

      def persistence = (@persistence ||= ContextPersistence.new(graphs:, scope:, intent_id: parsed.fetch(:intent_id)))

      def freshness = (@freshness ||= ContextFreshness.new(graphs:, scope:, source:))
    end
  end
end
