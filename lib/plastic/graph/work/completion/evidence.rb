# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      module Completion
        # The evidence of a delivered close, built from rows: each criterion key with the done nodes that serve it and their findings.
        class Evidence
          def initialize(retrieval, intent_id)
            @nodes = retrieval.nodes(intent_id).select(&:verified?)
          end

          def by_criterion(keys) = keys.to_h { |key| [key, evidence_of(key)] }

          private

          def evidence_of(key) = @nodes.select { |node| node.serves?(key) }.map(&:evidence).join("; ")
        end
      end
    end
  end
end
