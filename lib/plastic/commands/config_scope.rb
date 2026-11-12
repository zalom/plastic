# frozen_string_literal: true

require_relative "../config"

module Plastic
  module Commands
    # What the config commands share: the --harness option, the merged
    # settings it names, and the refusal of a key the settings do not hold.
    module ConfigScope
      ON_OFF = [true, false].freeze

      def self.included(command)
        command.opens_no_store
        command.option :harness, switch: "--harness NAME", text: "the harness whose settings to use; the global settings when left out"
      end

      private

      def config = (@config ||= Plastic::Config.new(scope.plastic_home, harness: parsed[:harness]))

      def current(key)
        config.entries.fetch(key) { raise CLI::Command::Usage, "no setting #{key}; plastic config list names them" }
      end

      def harness_words = parsed[:harness].then { |name| name ? " --harness #{name}" : "" }
    end
  end
end
