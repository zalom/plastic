# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Intent
      # Records a report of an intent, a file in resources/output/reports/, so the sync reads it. The owner's words that
      # asked for it must appear in an owner message of this store or of this session; a report the setting
      # reports.mandatory names needs no words. The record is a `reported` work log line with the path, its sha256 and
      # the words, and one line under `## Reports` in the outcome.
      class Report < Routine
        intent_subject
        argument :path, label: "PATH", text: "the report, a path inside the intent folder under resources/output/reports/"
        option :asked, switch: "--asked WORDS", text: "the owner's words that asked for the report"
        reads :work
        writes :knowledge
        prints :intent

        workflow :code_report_intent, next: :noop
      end
    end
  end
end
