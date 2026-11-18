# frozen_string_literal: true

require_relative "../roadmap"
require_relative "counted"

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        # Marks an item of a roadmap: dropped by the owner, or opened as an intent. Each call says whether a row changed.
        class ItemMarks
          DROP_SQL = "UPDATE roadmap_items SET mark = 'dropped', updated_at = :now " \
            "WHERE origin_id = :origin AND roadmap = :roadmap AND item = :item"
          OPEN_SQL = "UPDATE roadmap_items SET intent_id = :intent_id, updated_at = :now " \
            "WHERE origin_id = :origin AND roadmap = :roadmap AND item = :item"

          def initialize(databases, retrieval, clock:)
            @databases = databases
            @retrieval = retrieval
            @clock = clock
          end

          def drop_item(slug, item) = update(DROP_SQL, roadmap: slug, item:)

          # Records the intent an item was opened as.
          def open_item(slug, item, intent_id) = update(OPEN_SQL, roadmap: slug, item:, intent_id:)

          private

          def update(sql, **binds)
            now = Plastic.timestamp(@clock.now)
            Counted.new(@databases.fetch(:store)).changed do |batch|
              batch.write(:roadmap_items, sql, now:, origin: @retrieval.origin_id, **binds)
            end
          end
        end
      end
    end
  end
end
