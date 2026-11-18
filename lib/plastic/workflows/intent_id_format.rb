# frozen_string_literal: true

require_relative "../errors"

module Plastic
  module Workflows
    # The shape of an intent id: digits, then letters or digits.
    module IntentIdFormat
      SHAPE = /\A\d+[a-z0-9]*\z/

      def self.validate(id)
        raise Usage, "invalid intent id #{id.inspect}" unless SHAPE.match?(id)
      end
    end
  end
end
