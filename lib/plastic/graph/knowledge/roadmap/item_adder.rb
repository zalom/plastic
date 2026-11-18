# frozen_string_literal: true

require_relative "../roadmap"
require_relative "rows"
require_relative "standing"

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        # Adds an item to a batch of a roadmap, with the edges that make it wait for other items.
        class ItemAdder
          def initialize(databases, retrieval, clock:)
            @databases = databases
            @retrieval = retrieval
            @clock = clock
          end

          # Returns [item, problem, kind]; kind is :failure or :refusal, nil on success.
          def add_item(slug, item, batch_position, fields:, needs:)
            standing = Standing.new(@databases, @retrieval, slug)
            needed = Array(needs)
            problem, kind = standing.addition_problem(item, batch_position, needed)
            return [nil, problem, kind] if problem

            write(standing, item, batch_position, fields, needed)
            [standing.row_of(item), nil, nil]
          end

          private

          def write(standing, item, batch_position, fields, needs)
            rows = Rows.new(standing.slug, stamp)
            position = standing.new_item_position(item, batch_position)
            inserts = needs.map { |from| [:roadmap_edges, rows.edge(from, item)] }
            inserts.unshift([:roadmap_items, rows.item(item, batch_position, position, fields)]) if position
            store.transaction { |batch| batch.insert_rows(inserts) }
          end

          def stamp = Plastic.timestamp(@clock.now)

          def store = @databases.fetch(:store)
        end
      end
    end
  end
end
