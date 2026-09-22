# frozen_string_literal: true

require_relative "intent_command"

# `plastic intent end` - closes an intent as delivered or abandoned
# (`end-intent`, run through Legacy). end-intent's own exit code 4 is a
# pre-flight refusal (a live foreign session holds the delivery lock), not
# the exit 3 Legacy's generic contract turns into a Refusal on its own, so
# this command maps it by hand rather than through Legacy#run.
module Plastic
  class CLI
    module Commands
      class IntentEnd < IntentCommand
        USAGE_LINE = 'plastic intent end ID --delivered|--abandoned --summary "TEXT" [--note "TEXT"] [--dry-run] [--json]'

        REFUSAL_STATUS = 4

        SUMMARY_GUIDANCE = [
          "a good summary is written for the reader deciding whether to merge, release, or accept",
          "delivered: what shipped, impact and risk first, in plain language, never the checklist",
          "abandoned: why, and the trail if part of the work was dropped mid-flight"
        ].freeze

        def call
          raise Usage, "choose only one of --delivered or --abandoned" if options[:delivered] && options[:abandoned]
          raise Usage, "one of --delivered or --abandoned is required" unless disposition
          raise Usage, SUMMARY_GUIDANCE.join("\n") if options[:summary].to_s.empty?

          status = legacy.run("end-intent", *end_intent_arguments)
          raise Refusal, "end-intent needs the owner: the delivery lock is held" if status == REFUSAL_STATUS
          raise Failure, "end-intent exited #{status}" unless status.zero?

          @output.next_step("plastic status", because: "the intent moved out of Active")
        end

        private

        def disposition
          return "delivered" if options[:delivered]
          "abandoned" if options[:abandoned]
        end

        def switches(parser)
          parser.on("--delivered") { @options[:delivered] = true }
          parser.on("--abandoned") { @options[:abandoned] = true }
          parser.on("--summary TEXT") { |v| @options[:summary] = v }
          parser.on("--note TEXT") { |v| @options[:note] = v }
          parser.on("--dry-run") { @options[:dry_run] = true }
        end

        def end_intent_arguments
          intent_dir
          args = ["--store", scope.store, "--id", id, "--disposition", disposition,
            "--outcome-summary", options[:summary]]
          args += ["--index-note", options[:note]] if options[:note]
          args << "--dry-run" if options[:dry_run]
          args
        end
      end
    end
  end
end
