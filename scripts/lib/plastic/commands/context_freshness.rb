# frozen_string_literal: true

module Plastic
  module Commands
    # Reports whether saved evidence still describes the current source state.
    class ContextFreshness
      def initialize(source:)
        @source = source
      end

      def call(document)
        { "evidence" => document.fetch("evidence").map { |reference| evidence_state(document, reference) } }
      end

      private

      attr_reader :source

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

      def strip_revision(reference) = reference.sub(/\?revision=[0-9a-f]{64}\z/, "")
    end
  end
end
