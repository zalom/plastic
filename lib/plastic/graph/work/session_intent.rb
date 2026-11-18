# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      # The intent one session is working on: the intent of a node it holds, else the intent
      # of the newest work log line it wrote. An intent whose work is over is never the answer.
      class SessionIntent
        def initialize(retrieval, session_id)
          @retrieval = retrieval
          @session_id = session_id
        end

        def intent = held_intent || logged_intent

        # The nodes this session holds in an intent whose work is not over.
        def claims = @claims ||= @retrieval.claimed_nodes.select { |node| node.claimed_by == @session_id && unfinished?(node.intent_id) }

        private

        def held_intent
          held = claims.first
          held && @retrieval.intent(held.intent_id)
        end

        def logged_intent
          @retrieval.structure.logged_intent_ids(@session_id).lazy.filter_map { |intent_id| @retrieval.intent(intent_id) }.find { |found| !found.closed? }
        end

        def unfinished?(intent_id) = @retrieval.intent(intent_id)&.closed? == false
      end
    end
  end
end
