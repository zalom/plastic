# frozen_string_literal: true

require_relative "../roadmap"

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        # The rows of one roadmap as one write builds them, all stamped with the same time.
        class Rows
          def initialize(slug, now)
            @slug = slug
            @now = now
          end

          def roadmap = { slug: @slug, title: @slug, goal: nil, opened_at: @now, updated_at: @now }

          def batch(position, fields) = { roadmap: @slug, position:, **fields.words, updated_at: @now }

          def item(item, batch_position, position, fields)
            { roadmap: @slug, item:, batch: batch_position, position:, **fields.words, intent_id: nil, mark: nil, updated_at: @now }
          end

          def edge(from, to) = { roadmap: @slug, from:, to:, kind: "after" }

          def log(position, text, session_id) = { roadmap: @slug, position:, at: @now, text:, session_id: }
        end
      end
    end
  end
end
