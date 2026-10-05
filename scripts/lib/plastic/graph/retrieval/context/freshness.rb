# frozen_string_literal: true

require_relative "evidence"
require_relative "../../retrieval_graph"

module Plastic
  module Graph
    module Retrieval
      module Context
        # Reports whether saved evidence still describes the current source state.
        class Freshness
          def initialize(source:)
            @source = source
          end

          def call(document)
            { "evidence" => document.fetch("evidence").map { |reference| evidence_state(document, reference) } }
          end

          private

          attr_reader :source

          def evidence_state(document, reference)
            Retrieval::Context::Evidence.new(document:, reference:, retrieval: source.retrieval(reference)).state
          rescue RetrievalGraph::MissingReference
            missing_or_stale(reference)
          end

          def missing_or_stale(reference)
            retrieval = source.retrieval(reference)
            retrieval.fetch_reference(reference)
            { "uri" => reference, "state" => "stale" }
          rescue RetrievalGraph::MissingReference
            { "uri" => reference, "state" => "missing" }
          end
        end
      end
    end
  end
end
