# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      # The last work log lines of one intent, as a session recap and a
      # resume both print them.
      class LastLogLines
        def initialize(retrieval, count)
          @retrieval = retrieval
          @count = count
        end

        def lines(intent_id) = @retrieval.work_log(intent_id).last(@count).map(&:line)
      end
    end
  end
end
