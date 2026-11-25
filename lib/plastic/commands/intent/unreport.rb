# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Intent
      # Removes a report recorded by mistake with `plastic intent report`: the rows that hold it, its line under
      # `## Reports` in the outcome, and its file, which `--to-tmp` moves to resources/tmp/ instead of deleting it. The
      # work log keeps the `reported` line and gains a `removed` line with the reason; a closed intent also gets an
      # `amended` line for its changed outcome.
      class Unreport < Routine
        intent_subject
        argument :path, label: "PATH", text: "the recorded report, a path inside the intent folder under resources/output/reports/"
        option :reason, switch: "--reason TEXT", required: true, text: "why the report is removed, kept on the removed line of the work log"
        option :to_tmp, switch: "--to-tmp", default: false, text: "move the file to resources/tmp/ instead of deleting it"
        previews
        reads :work
        writes :work, :knowledge, :retrieval
        prints :intent

        workflow :code_unreport_intent, next: :noop
      end
    end
  end
end
