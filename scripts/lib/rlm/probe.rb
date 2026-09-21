# frozen_string_literal: true

require_relative "corpus"

module RLM
  class Probe
    STOP_WORDS = %w[a an and are as at be by do does for from how in is it of on or that the this to was what when where which who why with].freeze
    DEFAULT_LIMIT = 10

    def initialize(corpus, limit: DEFAULT_LIMIT)
      @corpus = corpus
      @limit = limit
    end

    def call(question)
      hits = terms(question).flat_map { |term| @corpus.call([term], @limit) }
      hits.group_by { |row| row["id"] }.values
        .map { |rows| rows.first.merge("score" => rows.size) }
        .sort_by.with_index { |row, index| [-row["score"], index] }
        .first(@limit)
    end

    private

    def terms(question)
      question.downcase.scan(/[[:alnum:]]+/).uniq - STOP_WORDS
    end
  end
end
