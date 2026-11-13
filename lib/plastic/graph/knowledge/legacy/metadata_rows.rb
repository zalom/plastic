# frozen_string_literal: true

require_relative "decisions"
require_relative "originals"
require_relative "roadmap_migration"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # Writes the decisions, the kept originals and the roadmaps of one legacy store.
        class MetadataRows
          def initialize(graphs, folder, counts)
            @graphs = graphs
            @folder = folder
            @counts = counts
          end

          def call(read)
            write_decisions(read.decisions)
            keep_originals(read.originals)
            RoadmapMigration.new(@graphs, @folder.root, @counts).call(read.parsed)
          end

          private

          def write_decisions(decisions) = Decisions.new.write_decisions(@graphs.databases, decisions, @counts)

          def keep_originals(originals) = Originals.new(@graphs.databases, @counts).keep_changed_originals(@folder, originals)
        end
      end
    end
  end
end
