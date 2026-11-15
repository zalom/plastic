# frozen_string_literal: true

require_relative "cluster_part"
require_relative "link_part"

module Plastic
  module Graph
    module Prints
      # The parts of store/index.json that carry a digest of their own: the clusters and the links.
      module Parts
        ALL = [ClusterPart, LinkPart].freeze

        module_function

        def path?(path) = ALL.any? { |part| part.path?(path) }

        def call(retrieval) = ALL.map { |part| part.call(retrieval) }

        # The digest of the part `path` in the text of an index file.
        def file_digest(path, text) = ALL.find { |part| part.path?(path) }.file_digest(text)
      end
    end
  end
end
