# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      # The intent `plastic next` picks: the one this session holds a live lock
      # on in this store, else the only active intent, else the only open one.
      class NextPick
        def initialize(retrieval, session)
          @retrieval = retrieval
          @session = session
        end

        # The one intent to work on, nil when none stands out alone.
        def intent = (candidates.size == 1) ? candidates.first : nil

        def ambiguous? = candidates.size > 1

        def none? = candidates.empty?

        # The intents the pick chooses among: the locked ones, else the active, else the open.
        def candidates
          @candidates ||= [locked_intents, by_status("active"), by_status("open")].find { |found| found.any? } || []
        end

        private

        def locked_intents
          store = @retrieval.store
          ids = @retrieval.locks_of(@session).select { |lock| lock.store == store && @retrieval.liveness(lock).live? }.map(&:intent_id)
          @retrieval.intents.select { |intent| intent.open? && ids.include?(intent.intent_id) }
        end

        def by_status(status) = @retrieval.intents.select { |intent| intent.status == status }
      end
    end
  end
end
