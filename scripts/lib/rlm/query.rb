# frozen_string_literal: true

require_relative "probe"

module RLM
  class Query
    DEFAULT_LIMIT = 3

    def initialize(probe, judge: nil, limit: DEFAULT_LIMIT)
      @probe = probe
      @judge = judge
      @limit = limit
    end

    def call(question)
      rows = @probe.call(question)
      return rows unless @judge && rows.size > @limit

      @judge.call(question, rows)
    end
  end
end
