# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Records the verdict of the next review round, with the findings behind it.
    class IntentVerdict < Routine
      VERDICTS = %w[accept revise].freeze

      intent_subject
      argument :verdict, label: "accept|revise", text: "the verdict of this review round"
      argument :findings, label: "TEXT", text: "what the review showed"
      writes :work

      workflow :code_prepare_verdict do
        on :recording, next: :code_record_verdict
      end
      workflow :code_record_verdict, next: :noop

      def call(*)
        verdict_problem&.then { |text| raise CLI::Command::Usage, text }

        super
      end

      private

      def verdict_problem
        return "the verdict takes accept or revise" unless VERDICTS.include?(parsed[:verdict])

        "the findings need text" if parsed[:findings].to_s.strip.empty?
      end
    end
  end
end
