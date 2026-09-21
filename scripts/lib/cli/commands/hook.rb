# frozen_string_literal: true

require "English"
require_relative "../command"
require_relative "../legacy"

module Plastic
  class CLI
    module Commands
      class Hook < Command
        USAGE_LINE = "plastic hook EVENT"
        EVENTS = %w[call-budget capture close record savepoint session-start stop].freeze

        DEFAULT_RUNNER = lambda do |path|
          system(path)
          Legacy.exit_code($CHILD_STATUS)
        end

        def self.call(argv, runner: DEFAULT_RUNNER, **seams)
          return super(argv, **seams) unless EVENTS.include?(argv.first)

          root = Legacy.new(env: seams.fetch(:env, ENV)).package_root
          runner.call(File.join(root, "hooks", argv.first))
        end

        def call
          raise Usage, "EVENT is one of #{EVENTS.join(", ")}"
        end
      end
    end
  end
end
