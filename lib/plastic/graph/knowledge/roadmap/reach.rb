# frozen_string_literal: true

require_relative "../roadmap"

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        # Which items a roadmap's edges lead to, to tell whether a new edge would close a loop.
        class Reach
          LOOP_SQL = <<~SQL
            SELECT 1 WHERE EXISTS (
              WITH RECURSIVE reach(id) AS (
                SELECT "to" FROM roadmap_edges WHERE origin_id = :origin AND roadmap = :roadmap AND "from" = :to
                UNION
                SELECT roadmap_edges."to" FROM roadmap_edges JOIN reach ON roadmap_edges."from" = reach.id
                WHERE roadmap_edges.origin_id = :origin AND roadmap_edges.roadmap = :roadmap
              )
              SELECT 1 FROM reach WHERE id = :from
            )
          SQL

          def initialize(databases, retrieval, slug)
            @databases = databases
            @retrieval = retrieval
            @slug = slug
          end

          def loop?(from, to)
            from == to || !@databases.fetch(:store).row(LOOP_SQL, origin: @retrieval.origin_id, roadmap: @slug, from:, to:).nil?
          end
        end
      end
    end
  end
end
