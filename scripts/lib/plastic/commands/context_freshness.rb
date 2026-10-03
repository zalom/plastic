# frozen_string_literal: true

require_relative "context_evidence"

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
        ContextEvidence.new(document:, reference:, retrieval: source.retrieval(reference)).state
      rescue Graph::RetrievalGraph::MissingReference
        missing_or_stale(reference)
      end

      def missing_or_stale(reference)
        retrieval = source.retrieval(reference)
        retrieval.fetch_reference(reference)
        { "uri" => reference, "state" => "stale" }
      rescue Graph::RetrievalGraph::MissingReference
        { "uri" => reference, "state" => "missing" }
      end
    end
  end
end
