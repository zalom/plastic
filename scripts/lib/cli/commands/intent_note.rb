# frozen_string_literal: true

require_relative "intent_command"

# `plastic intent note` - appends a savepoint line to an intent
# (`savepoint-note`, run through Legacy). `--kind` defaults to Report, the
# most general of the three savepoint kinds, for a note that names no kind
# of its own.
module Plastic
  class CLI
    module Commands
      class IntentNote < IntentCommand
        USAGE_LINE = 'plastic intent note ID "TEXT" [--kind Review|Commit|Report] [--json]'

        SCRIPT = "savepoint-note"
        AFTER = "plastic intent show ID"
        BECAUSE = "the state screen carries the savepoint trail this just wrote"

        DEFAULT_KIND = "Report"

        def call
          raise Usage, "the note text is required" if text.to_s.empty?

          super
        end

        private

        def text
          arguments[1]
        end

        def switches(parser)
          parser.on("--kind KIND") { |v| @options[:kind] = v }
        end

        def script_arguments
          [intent_dir, "--kind", options[:kind] || DEFAULT_KIND, "--text", text]
        end
      end
    end
  end
end
