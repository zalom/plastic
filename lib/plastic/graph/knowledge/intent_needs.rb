# frozen_string_literal: true

require_relative "../edge_walk"

module Plastic
  module Graph
    module Knowledge
      # The needs links between the intents of one store: an intent that needs another waits until that one is
      # done or abandoned. It answers what an intent still waits on, which intents wait, and whether a new link
      # would close a loop.
      class IntentNeeds
        FINISHED = %w[done abandoned].freeze

        def initialize(retrieval)
          @retrieval = retrieval
        end

        # The ids `id` needs, in the order of their links.
        def of(id) = pairs.select { |from, _to| from == id }.map(&:last)

        # The ids `id` needs that are not finished.
        def waiting_on(id) = of(id).reject { |needed| finished?(needed) }

        # Every intent of `intents` that waits, with the ids it waits on.
        def blocked(intents) = intents.map(&:intent_id).to_h { |id| [id, waiting_on(id)] }.reject { |_id, waits| waits.empty? }

        # The intents from `from` through `to` and back to `from` that a link from `from` to `to` would close, or nil.
        def loop_path(from, to)
          path = EdgeWalk.new(pairs).path(to, from)
          path && [from, *path]
        end

        private

        def finished?(id) = FINISHED.include?(@retrieval.intent(id)&.status)

        def pairs = @pairs ||= @retrieval.every_link.select(&:needs?).map(&:ends)
      end
    end
  end
end
