# frozen_string_literal: true

require_relative "index_file"

module Plastic
  module Graph
    module Knowledge
      class Reader
        # The clusters of store/index.json as a file of their own: it replaces the clusters this home holds with the
        # ones the file lists, and leaves the clusters of another origin and every other row of the index.
        class ClusterFile < IndexFile
          def apply(batch) = batch.remove(:clusters).put_all(:clusters, members)
        end
      end
    end
  end
end
