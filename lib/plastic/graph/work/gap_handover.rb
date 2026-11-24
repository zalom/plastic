# frozen_string_literal: true

require_relative "verdict/rounds"

module Plastic
  module Graph
    module Work
      # Writes the work log line of the owner's handover of an intent's last gap to a follow-up intent.
      class GapHandover
        def initialize(log)
          @log = log
        end

        def write(intent_id, follow_up, reason)
          @log.recorded { @log.line(intent_id, Verdict::Rounds::HANDOVER_KIND, "Handed over to #{follow_up} by the owner: #{reason}") }
        end
      end
    end
  end
end
