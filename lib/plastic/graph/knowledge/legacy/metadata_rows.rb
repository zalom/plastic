# frozen_string_literal: true

require_relative "decision_writer"
require_relative "decisions"
require_relative "originals"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # Writes the decisions and the kept originals of one legacy store.
        class MetadataRows
          def initialize(graphs, folder, counts)
            @graphs = graphs
            @folder = folder
            @counts = counts
          end

          def call(read)
            write_decisions(read.decisions)
            keep_originals(read.originals)
          end

          private

          def write_decisions(decisions) = DecisionWriter.new(@graphs.databases, @counts, clock: @graphs.retrieval.clock).call(decisions)

          def keep_originals(originals) = Originals.new(@graphs.databases, @counts, clock: @graphs.retrieval.clock).keep_changed_originals(@folder, originals)
        end
      end
    end
  end
end
