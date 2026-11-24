# frozen_string_literal: true

require_relative "ranker"
require_relative "read_only_store"

module SearchCheck
  # The report lines of a run: one for each question and a total.
  class Check
    def initialize(arguments, questions)
      @questions = questions
      @limit = arguments.limit
      @terms = ->(question) { question.public_send(arguments.field) }
      @ranker = Ranker.new(ReadOnlyStore.new(arguments.store), @limit)
    end

    def lines
      ranks = @questions.map { |question| @ranker.call(question.answers, @terms.call(question)) }
      [*@questions.zip(ranks).map { |question, rank| question.line(rank) }, "total #{ranks.compact.size}/#{ranks.size} in the first #{@limit}"]
    end
  end
end
