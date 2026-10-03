# frozen_string_literal: true

module Plastic
  module Commands
    # Reports whether saved evidence and architecture still describe current source state.
    class ContextFreshness
      def initialize(graphs:, scope:, source:)
        @graphs = graphs
        @scope = scope
        @source = source
      end

      def call(document)
        { "evidence" => document.fetch("evidence").map { |reference| evidence_state(document, reference) },
          "architecture" => architecture_state(document.fetch("architecture")) }
      end

      private

      attr_reader :graphs, :scope, :source

      def evidence_state(document, reference)
        retrieval = source.retrieval(reference)
        retrieval.fetch_reference(reference)
        current = retrieval.fetch_reference(strip_revision(reference))
        archived = retrieval.archived?(current.fetch(:intent_id))
        state = fresh?(document, reference, current, archived) ? "fresh" : "stale"
        { "uri" => reference, "state" => state, "archived" => archived }
      rescue Graph::RetrievalGraph::MissingReference
        missing_or_stale(reference)
      end

      def fresh?(document, reference, current, archived)
        current.fetch(:uri) == reference && document.fetch("archive_states", {}).fetch(reference, archived) == archived
      end

      def missing_or_stale(reference)
        retrieval = source.retrieval(reference)
        retrieval.fetch_reference(reference)
        { "uri" => reference, "state" => "stale" }
      rescue Graph::RetrievalGraph::MissingReference
        { "uri" => reference, "state" => "missing" }
      end

      def architecture_state(architecture)
        receipt = stored_receipt(architecture.fetch("provider"))
        return status(architecture, "missing") unless receipt.fetch("available", true)

        state = (receipt.fetch("revision") == architecture.fetch("revision")) ? "fresh" : "stale"
        status(architecture, state)
      rescue Errno::ENOENT, JSON::ParserError, KeyError
        status(architecture, "missing")
      end

      def status(architecture, state)
        { "provider" => architecture.fetch("provider"), "revision" => architecture.fetch("revision"), "state" => state }
      end

      def stored_receipt(provider)
        row = graphs.databases.fetch(:knowledge).row("SELECT data FROM architecture_receipts WHERE provider = :provider AND origin_id = :origin",
          provider:, origin: graphs.retrieval.origin_id)
        return JSON.parse(row.fetch("data")) if row

        JSON.parse(File.read(receipt_path(provider)))
      end

      def strip_revision(reference) = reference.sub(/\?revision=[0-9a-f]{64}\z/, "")

      def receipt_path(provider) = File.join(scope.root, "architecture", "#{provider}.json")
    end
  end
end
