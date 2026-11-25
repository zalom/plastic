# frozen_string_literal: true

require_relative "../../lib/plastic/graph/retrieval/search"

module SearchCheck
  # The rank of the first known answer among the first `limit` intents a search returns, or nil.
  class Ranker
    def initialize(store, limit)
      @search = Plastic::Graph::Retrieval::Search.new(store, origin: Struct.new(:id).new(store.origin_id))
      @limit = limit
    end

    def call(answers, terms) = intents(terms).index { |id| answers.include?(id) }&.+(1)

    private

    attr_reader :search, :limit

    def intents(terms)
      hits = search.call(terms, limit: Plastic::Graph::Retrieval::Search::SEARCH_LIMIT)
      hits.map { |hit| hit.fetch("intent_id") }.uniq.first(limit)
    rescue Plastic::Graph::RetrievalGraph::InvalidSearch
      []
    end
  end
end
