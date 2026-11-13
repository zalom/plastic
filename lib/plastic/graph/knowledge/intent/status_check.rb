# frozen_string_literal: true

require_relative "../intent"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # Why a new intent cannot take a status and a reason, or nil when they fit.
        module StatusCheck
          NEW = %w[open parked future].freeze

          module_function

          def problem(status: "open", reason: nil)
            return "a new intent takes the status open, parked or future, not #{status}" unless NEW.include?(status)

            parked = status == "parked"
            return "a parked intent needs a reason: pass --reason TEXT" if parked && reason.to_s.strip.empty?

            "--reason belongs to a parked intent: pass --status parked" if reason && !parked
          end
        end
      end
    end
  end
end
