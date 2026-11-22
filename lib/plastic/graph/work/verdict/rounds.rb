# frozen_string_literal: true

require_relative "../../rows/verdict"

module Plastic
  module Graph
    module Work
      class Verdict
        # The review rounds of one intent: the two rounds every intent has, plus one for each `granted` line of its work log.
        class Rounds
          GRANT_KIND = "granted"

          def initialize(retrieval, intent_id)
            @retrieval = retrieval
            @intent_id = intent_id
          end

          def granted = @retrieval.structure.work_log(@intent_id).count { |line| line.kind == GRANT_KIND }

          def allowed = Verdict::ROUNDS + granted

          def used = @retrieval.structure.verdicts(@intent_id).size

          def left? = used < allowed
        end
      end
    end
  end
end
