# frozen_string_literal: true

module Plastic
  module Graph
    # Coordinates validation, capture, and completion of one archive request.
    class ArchiveOperation
      def initialize(retrieval, guard, capture, completion)
        @retrieval = retrieval
        @guard = guard
        @capture = capture
        @completion = completion
      end

      def call(intent_id)
        intent = retrieval.intent(intent_id)
        return missing(intent_id) unless intent
        return complete(intent) if retrieval.archived?(intent_id)

        archive(intent)
      end

      private

      attr_reader :capture, :completion, :guard, :retrieval

      def archive(intent)
        problem = guard.problem(intent)
        return refused(problem) if problem

        capture.capture(intent)
        complete(intent)
      end

      def complete(intent)
        completion.call(intent)
        [true, nil, nil]
      end

      def missing(intent_id) = [false, "no intent #{intent_id}", :failure]

      def refused(problem) = [false, problem, :refusal]
    end
  end
end
