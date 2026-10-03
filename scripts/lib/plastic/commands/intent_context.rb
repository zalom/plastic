# frozen_string_literal: true

require_relative "../cli/command"
require_relative "../graph"
require_relative "context_persistence"
require_relative "context_freshness"
require_relative "context_source"
require_relative "context_submission"
require_relative "context_documents"
require_relative "context_exchange"
require_relative "context_owner"
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
        owner.validate(intent_id)
        output.row("context", exchange.call)
        output.next_step("none", because: "the retrieval context was read")
      rescue Errno::ENOENT, JSON::ParserError => error
        message = error.message
        raise CLI::Command::Usage, message
      rescue Graph::RetrievalGraph::MaintenanceRequired, Graph::RetrievalGraph::MissingReference, KeyError => error
        message = error.message
        raise CLI::Command::Failure, message
      end

      private

      def intent_id = parsed.fetch(:intent_id)

      def owner = (@owner ||= ContextOwner.new(scope))

      def exchange = (@exchange ||= ContextExchange.new(graphs:, scope:, intent_id:, submission_path: parsed[:from]))
    end
  end
end
