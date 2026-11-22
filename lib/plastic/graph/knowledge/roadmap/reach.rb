# frozen_string_literal: true

require_relative "../../edge_walk"
require_relative "../roadmap"

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        # Which items a roadmap's edges lead to, to tell whether a new edge would close a loop.
        class Reach
          EDGES_SQL = "SELECT \"from\", \"to\" FROM roadmap_edges WHERE origin_id = :origin AND roadmap = :roadmap"

          def initialize(databases, retrieval, slug)
            @databases = databases
            @retrieval = retrieval
            @slug = slug
          end

          def loop?(from, to) = !loop_path(from, to).nil?

          # The items an edge from `from` to `to` would close a loop through, from `from` back to `from`, or nil when it closes none.
          def loop_path(from, to)
            path = EdgeWalk.new(pairs).path(to, from)
            path && [from, *path]
          end

          private

          def pairs = @databases.fetch(:store).rows(EDGES_SQL, origin: @retrieval.origin_id, roadmap: @slug).map { |row| [row.fetch("from"), row.fetch("to")] }
        end
      end
    end
  end
end
