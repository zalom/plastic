# frozen_string_literal: true

require_relative "../config"

module Plastic
  class CLI
    # What the config commands share: the --harness option and the merged
    # settings it names.
    module ConfigScope
      ON_OFF = [true, false].freeze

      def self.included(command)
        command.opens_no_store
        command.option :harness, switch: "--harness NAME", text: "the harness whose settings to use; the global settings when left out"
      end

      private

      def config = (@config ||= Plastic::Config.new(scope.plastic_home, harness: parsed[:harness], clock: environment.clock))

      def harness_words = parsed[:harness].then { |name| name ? " --harness #{name}" : "" }
    end
  end
end
