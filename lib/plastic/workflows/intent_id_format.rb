# frozen_string_literal: true

require_relative "../cli/command/usage"

module Plastic
  module Workflows
    # The shape of an intent id: digits, then letters or digits.
    module IntentIdFormat
      SHAPE = /\A\d+[a-z0-9]*\z/

      def self.validate(id)
        raise CLI::Command::Usage, "invalid intent id #{id.inspect}" unless SHAPE.match?(id)
      end
    end
  end
end
