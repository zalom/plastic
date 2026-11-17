# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      # The intent `plastic next` picks: the one this session holds a live claim
      # on in this store, else the only intent in progress, else the only open one.
      class NextPick
        def initialize(retrieval, session, now:)
          @retrieval = retrieval
          @session = session
          @now = now
        end

        # The one intent to work on, nil when none stands out alone.
        def intent = (candidates.size == 1) ? candidates.first : nil

        def ambiguous? = candidates.size > 1

        def none? = candidates.empty?

        # The intents the pick chooses among: the claimed ones, else those in progress, else the open.
        def candidates
          @candidates ||= [claimed_intents, by_status("in_progress"), by_status("open")].find { |found| found.any? } || []
        end

        private

        def claimed_intents
          ids = @retrieval.claimed_nodes.select { |node| node.claimed_by == @session && !node.lapsed?(@now) }.map(&:intent_id)
          @retrieval.intents.select { |intent| intent.open? && ids.include?(intent.intent_id) }
        end

        def by_status(status) = @retrieval.intents.select { |intent| intent.status == status }
      end
    end
  end
end
