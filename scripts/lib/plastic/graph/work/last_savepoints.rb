# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      # The last savepoint lines of one intent, as a session recap and a
      # resume both print them.
      class LastSavepoints
        def initialize(retrieval, count)
          @retrieval = retrieval
          @count = count
        end

        def lines(intent_id) = @retrieval.savepoints(intent_id).last(@count).map(&:line)
      end
    end
  end
end
