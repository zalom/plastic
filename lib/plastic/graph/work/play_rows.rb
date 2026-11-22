# frozen_string_literal: true

require_relative "intent_rows"
require_relative "../retrieval/work_context"

module Plastic
  module Graph
    module Work
      # The rows of the work in play for a project digest: the intents, then the passages that the retrieval graph gives
      # for the intents in progress.
      class PlayRows
        def initialize(retrieval, slug)
          @retrieval = retrieval
          @slug = slug
        end

        def rows
          intents = @retrieval.intents
          [*IntentRows.new(intents, @slug).rows, *Retrieval::WorkContext.new(@retrieval, intents).rows]
        end
      end
    end
  end
end
