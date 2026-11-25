# frozen_string_literal: true

require "json"
require_relative "../../reader"
require_relative "../../store_folder"

module Plastic
  module Graph
    module Knowledge
      class Sync
        class SecondHome
          # The clusters of an index file that this home holds no clusters for.
          class Clusters
            def initialize(folder, retrieval, known)
              @folder = folder
              @retrieval = retrieval
              @known = known
            end

            def problems
              lacking = entries.map { |row| row[:intent_id] }.uniq - @known
              lacking.empty? ? {} : { StoreFolder::INDEX => "lists a cluster with #{lacking.map { |id| "intent #{id}" }.join(", ")}, which this home lacks" }
            end

            private

            def entries
              return [] unless @folder.exist?(StoreFolder::INDEX) && @retrieval.clusters.empty?

              Reader::IndexFile.new(@folder.read(StoreFolder::INDEX), @retrieval.origin_id).cluster_rows
            rescue JSON::ParserError, Invalid
              []
            end
          end
        end
      end
    end
  end
end
