# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      # What a path relative to a store folder names: a roadmap, the event log an older release kept beside it,
      # the context view of an intent, or its graph file.
      module StorePath
        module_function

        def roadmap_log(path) = path.sub(/\.md\z/, ".savepoint.md")

        def roadmap_log?(path) = path.end_with?(".savepoint.md")

        def context_view?(path) = path.match?(%r{\Astore/[^/]+/context\.json\z})

        def roadmap?(path) = path.to_s.start_with?("roadmaps/")

        def graph_file?(path) = path.match?(%r{\Astore/[^/]+/graph\.json\z})
      end
    end
  end
end
