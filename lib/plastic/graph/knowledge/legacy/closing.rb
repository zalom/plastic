# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # What the line of a closed, parked or future intent in INDEX.md gives: the disposition of the
        # finish, the reason in its text, and the closing date.
        module Closing
          REASONED = %w[parked future abandoned done].freeze
          SUPERSEDED = /superseded by/i
          DISPOSITIONS = { "done" => ->(_text) { "delivered" }, "abandoned" => ->(text) { text.to_s.match?(SUPERSEDED) ? "superseded" : "cancelled" } }.freeze

          module_function

          def of(status, text, date) = [DISPOSITIONS[status]&.call(text), (text if REASONED.include?(status) && text != "delivered"), date]
        end
      end
    end
  end
end
