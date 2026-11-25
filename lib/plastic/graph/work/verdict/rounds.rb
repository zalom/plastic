# frozen_string_literal: true

require_relative "../../rows/verdict"

module Plastic
  module Graph
    module Work
      class Verdict
        # The review rounds of one intent: the two rounds every intent has, plus one for each `granted` line of its work log.
        # A `handed_over` line is the owner's word that a follow-up intent takes over the last gap; it holds until a later grant.
        class Rounds
          GRANT_KIND = "granted"
          HANDOVER_KIND = "handed_over"

          def initialize(retrieval, intent_id)
            @retrieval = retrieval
            @intent_id = intent_id
          end

          def granted = owner_lines.count { |line| line.kind == GRANT_KIND }

          def allowed = Verdict::ROUNDS + granted

          def used = @retrieval.structure.verdicts(@intent_id).size

          def left? = used < allowed

          def handed_over? = owner_lines.last&.kind == HANDOVER_KIND

          private

          def owner_lines = @retrieval.structure.work_log(@intent_id).select { |line| [GRANT_KIND, HANDOVER_KIND].include?(line.kind) }
        end
      end
    end
  end
end
