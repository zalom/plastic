# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"

# `plastic auto lock` - inspects, repairs, or releases an intent's delivery
# lock (`plastic-lock status|fix|release --intent-dir DIR`, run through
# Legacy). The verb comes first, then the id, since the verb is what the
# table's two-token match consumes as part of the command name.
module Plastic
  class CLI
    module Commands
      class AutoLock < Command
        USAGE_LINE = "plastic auto lock status|fix|release ID [--json]"

        VERBS = %w[status fix release].freeze
        AFTER = {"status" => "plastic auto lock fix ID", "fix" => "plastic auto brief ID",
                 "release" => "plastic session summary"}.freeze
        BECAUSE = {"status" => "a stale or held lock is repaired by fix, not by re-arming",
                   "fix" => "a repaired lock is ready for the preamble again",
                   "release" => "the summary is what a freed lock leads to"}.freeze

        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        def call
          raise Usage, "VERB must be one of #{VERBS.join(", ")}" unless VERBS.include?(verb)

          status = legacy.run("plastic-lock", verb, "--intent-dir", intent_dir)
          raise Failure, "plastic-lock exited #{status}" unless status.zero?

          @output.next_step(AFTER.fetch(verb).sub("ID", id.to_s), because: BECAUSE.fetch(verb))
        end

        private

        def verb
          arguments[0]
        end

        def id
          arguments[1]
        end

        def intent_dir
          dir = scope.intent_dir(id)
          raise Failure, "no intent #{id.inspect} in #{scope.slug}; plastic status lists the ones that exist" unless dir

          dir
        end

        def legacy
          @legacy ||= Legacy.new(env: @env, runner: @runner)
        end
      end
    end
  end
end
