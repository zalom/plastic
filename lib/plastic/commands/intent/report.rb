# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Intent
      # Records a report of an intent, a file in resources/output/reports/, so the sync reads it. The record is a
      # `reported` work log line with the path and its sha256, and one line under `## Reports` in the outcome. Which work
      # needs a report is the guidance of PLASTIC.md and of `plastic help completion-and-done`.
      class Report < Routine
        intent_subject
        argument :path, label: "PATH", text: "the report, a path inside the intent folder under resources/output/reports/"
        reads :work
        writes :knowledge
        prints :intent

        workflow :code_report_intent, next: :noop
      end
    end
  end
end
