# frozen_string_literal: true

require_relative "../sync_selection"

module Plastic
  module Graph
    module Knowledge
      module Repair
        # The intent folders a repair leaves alone, because files would move under a session at work: a live driver claim
        # or a node claim that has not lapsed holds the intent, whichever session holds it, the calling one included.
        class Holds
          WHY = "a live driver or node claim holds the intent; run plastic intent repair again when the claim ends or lapses"

          def initialize(work, retrieval, now)
            @work = work
            @retrieval = retrieval
            @now = now
          end

          # The folders of `dirs` that a claim holds.
          def of(dirs) = dirs.select { |dir| held?(SyncSelection.intent_of(dir)) }.to_set

          private

          def held?(intent_id) = claimed.include?(intent_id) || @work.driven?(intent_id)

          def claimed = (@claimed ||= @retrieval.claimed_nodes.reject { |node| node.lapsed?(@now) }.to_set(&:intent_id))
        end
      end
    end
  end
end
