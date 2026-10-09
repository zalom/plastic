# frozen_string_literal: true

require_relative "../archive"

module Plastic
  module Graph
    module Knowledge
      class Archive
        # Coordinates validation, capture, and completion of one archive request.
        class Operation
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
            return refused(problem, intent) if problem

            capture.capture(intent)
            complete(intent)
          end

          def complete(intent)
            completion.call(intent)
            [true, nil, nil]
          end

          def missing(intent_id) = [false, "no intent #{intent_id}", :failure]

          def refused(problem, intent) = [false, problem, intent.archive_refusal ? :unfinished : :refusal]
        end
      end
    end
  end
end
