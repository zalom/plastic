# frozen_string_literal: true

module RLM
  class Corpus
    def initialize(search)
      @search = search
    end

    def call(terms, limit)
      @search.call(terms, limit)
    end
  end
end
