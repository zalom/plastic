# frozen_string_literal: true

require_relative "search/excerpt"

module Plastic
  module Graph
    module Retrieval
      # The context of the work in play: for each intent in progress, the best passages of the other intents for its
      # title, ranked by BM25. The count of intents, the count of passages and the length of each passage are bounded,
      # so a project digest stays small.
      class WorkContext
        INTENTS = 3
        PASSAGES = 2
        CANDIDATES = 8
        LENGTH = 200

        # The passage lines of one intent in progress.
        Lines = Data.define(:retrieval, :intent) do
          def to_a = hits.first(PASSAGES).map { |hit| "for #{intent.intent_id}: #{hit.fetch("intent_id")}/#{hit.fetch("path")} - #{text(hit)}" }

          private

          def hits = retrieval.search_current(intent.title, limit: CANDIDATES).reject { |hit| hit.fetch("intent_id") == intent.intent_id }

          def text(hit) = Search::Excerpt.new(intent.title).call(hit.fetch("body")).split.join(" ")[0, LENGTH]
        end

        def initialize(retrieval, intents)
          @retrieval = retrieval
          @started = intents.select { |intent| intent.status == "in_progress" }.first(INTENTS)
        end

        def rows = @started.flat_map { |intent| Lines.new(@retrieval, intent).to_a }.map { |text| ["context:", text] }
      end
    end
  end
end
