# frozen_string_literal: true

require_relative "intent_command"

# `plastic intent rule` - records one ruling in an intent's `## Insights`
# (`insight-append`, run through Legacy, stamped `--stage Why --author human`
# since a rule is always the owner's).
module Plastic
  class CLI
    module Commands
      class IntentRule < IntentCommand
        USAGE_LINE = 'plastic intent rule ID "TEXT" [--json]'

        SCRIPT = "insight-append"
        AFTER = "plastic intent show ID"
        BECAUSE = "the state screen reads Insights straight off the ledger this just wrote"

        def call
          raise Usage, "the ruling text is required" if text.to_s.empty?

          super
        end

        private

        def text
          arguments[1]
        end

        def script_arguments
          [intent_dir, text, "--stage", "Why", "--author", "human"]
        end
      end
    end
  end
end
