# frozen_string_literal: true

require_relative "verdict/rounds"

module Plastic
  module Graph
    module Work
      # Writes the work log line of the owner's grant of one review round.
      class RoundGrant
        def initialize(log)
          @log = log
        end

        def write(intent_id, reason)
          @log.recorded { @log.line(intent_id, Verdict::Rounds::GRANT_KIND, "Granted by the owner: #{reason}") }
        end
      end
    end
  end
end
