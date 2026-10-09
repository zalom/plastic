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

          def by_criterion(keys) = keys.to_h { |key| [key, served_by(key).map { |node| "#{node.id}: #{node.findings.strip}" }.join("; ")] }

          private

          def served_by(key) = @nodes.select { |node| node.criterion == key }
        end
      end
    end
  end
end
