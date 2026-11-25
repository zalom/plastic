# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      # What a path relative to a store folder names: the context view of an intent or its graph file.
      module StorePath
        module_function

        def context_view?(path) = path.match?(%r{\Astore/[^/]+/context\.json\z})

        def graph_file?(path) = path.match?(%r{\Astore/[^/]+/graph\.json\z})
      end
    end
  end
end
