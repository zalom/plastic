# frozen_string_literal: true

require_relative "../wiring"
require_relative "../cli/command"

module Plastic
  module Workflows
    # What the config workflows share: the settings the --harness option names,
    # the refusal of a key the settings do not hold, and the harness words a
    # next step repeats.
    class ConfigSettings
      ON_OFF = [true, false].freeze

      def initialize(context)
        @context = context
      end

      def entries = config.entries

      def set(key, value) = config.set(key, value)

      def problem = Plastic::Wiring.store(@context.scope.plastic_home).problem

      def current(key)
        entries.fetch(key) { raise Usage, "no setting #{key}; plastic config list names them" }
      end

      def harness_words = @context.harness.then { |name| name ? " --harness #{name}" : "" }

      private

      def config = (@config ||= Plastic::Wiring.config(@context.scope.plastic_home, harness: @context.harness, clock: @context.clock))
    end
  end
end
