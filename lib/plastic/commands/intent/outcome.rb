# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Intent
      # Writes the summary of the intent's outcome.md from the file that --from names. The title and every section
      # stay; `plastic intent note` writes the lines of the sections.
      class Outcome < Routine
        intent_subject
        option :from, switch: "--from FILE", required: true,
          text: "a file that holds the summary, plain text with no heading, written as the new revision of outcome.md"
        reads :work
        writes :knowledge, :retrieval
        prints :intent

        workflow :code_write_outcome, next: :noop
      end
    end
  end
end
