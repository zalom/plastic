# frozen_string_literal: true

require_relative "results/fusion"
require_relative "results/result"
require_relative "results/store"

module Plastic
  module Graph
    module Retrieval
      class Search
        # Reads per-store matches and merges them with reciprocal-rank fusion.
        class Results
          RRF_OFFSET = 60

          def initialize(plastic_home, terms, excerpt:, opener:)
            @plastic_home = plastic_home
            @opener = opener
            @terms = terms
            @excerpt = excerpt
          end

          def call(sources, limit)
            Search::Results::Fusion.new(sources.flat_map { |slug| store_rows(slug, limit) }, limit).call
          end

          private

          attr_reader :excerpt, :opener, :plastic_home, :terms

          def store_rows(slug, limit)
            retrieval = Search::Results::Store.new(plastic_home, slug, opener).retrieval
            retrieval.search_current(terms, limit:).each_with_index.map do |row, index|
              match = Search::Results::Match.new(retrieval, slug, row, index + 1, RRF_OFFSET)
              Search::Results::Result.new(match, excerpt:).to_h
            end
          end
        end
      end
    end
  end
end
